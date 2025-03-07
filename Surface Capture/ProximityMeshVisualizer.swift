import RealityKit
import ARKit
import Combine

class ProximityMeshVisualizer: NSObject, ARSessionDelegate {
    private var arView: ARView
    private var wireframeRoot: AnchorEntity
    private var meshAnchors: [UUID: [Entity]] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Configuration
    private let maxDistance: Float = 1.0  // 1 meter radius
    private let lineColor = UIColor.white
    private let lineThickness: Float = 0.001
    private let updateFrequency: TimeInterval = 0.1  // 10 updates per second
    
    private var updateTimer: Timer?
    private var isActive = false
    
    init(arView: ARView) {
        self.arView = arView
        
        // Create root entity for all wireframe elements
        wireframeRoot = AnchorEntity(world: .zero)
        
        // Call super.init() before any other initialization
        super.init()
        
        // Add the anchor entity to the scene
        arView.scene.addAnchor(wireframeRoot)
    }
    
    func start() {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            print("Scene mesh reconstruction not supported on this device")
            return
        }
        
        guard !isActive else { return }
        isActive = true
        
        // Configure AR session for mesh generation
        let configuration = ARWorldTrackingConfiguration()
        configuration.sceneReconstruction = .mesh
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        
        // Run the session with the configuration
        arView.session.run(configuration)
        
        // Set the session delegate to self for mesh updates
        arView.session.delegate = self
        
        // Schedule regular mesh updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateFrequency, repeats: true) { [weak self] _ in
            self?.updateMeshVisualization()
        }
    }
    
    func stop() {
        guard isActive else { return }
        isActive = false
        
        // Stop timer
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Remove all wireframe entities
        wireframeRoot.children.forEach { $0.removeFromParent() }
        meshAnchors.removeAll()
    }
    
    private func updateMeshVisualization() {
        guard isActive else { return }
        
        // Get current camera position and orientation
        guard let cameraTransform = arView.session.currentFrame?.camera.transform else { return }
        let cameraPosition = simd_make_float3(cameraTransform.columns.3)
        let cameraForward = -simd_make_float3(cameraTransform.columns.2)
        
        // Calculate focus point for proximity check
        let focusPoint = cameraPosition + (cameraForward * 0.5)
        
        // Update all mesh anchors
        let meshAnchors = arView.session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
        for anchor in meshAnchors {
            processMeshAnchor(anchor, cameraPosition: cameraPosition, focusPoint: focusPoint)
        }
    }
    
    private func processMeshAnchor(_ anchor: ARMeshAnchor, cameraPosition: SIMD3<Float>, focusPoint: SIMD3<Float>) {
        // Remove any existing visualization for this anchor
        if let existingEntities = self.meshAnchors[anchor.identifier] {
            existingEntities.forEach { $0.removeFromParent() }
        }
        
        // Create new wireframe representation
        let wireframeEntities = createWireframeForMesh(
            anchor: anchor,
            cameraPosition: cameraPosition,
            focusPoint: focusPoint
        )
        
        // If we have wireframe entities to show, add them to the scene
        if !wireframeEntities.isEmpty {
            wireframeEntities.forEach { wireframeRoot.addChild($0) }
            self.meshAnchors[anchor.identifier] = wireframeEntities
        } else {
            // No wireframe entities in range
            self.meshAnchors[anchor.identifier] = []
        }
    }
    
    private func createWireframeForMesh(anchor: ARMeshAnchor, cameraPosition: SIMD3<Float>, focusPoint: SIMD3<Float>) -> [Entity] {
        let geometry = anchor.geometry
        
        // Extract vertices from the mesh
        let vertexCount = geometry.vertices.count
        var vertices: [SIMD3<Float>] = []
        var vertexInRange: [Bool] = []
        
        // Get vertices and determine which are in range
        for i in 0..<vertexCount {
            let vertexPointer = geometry.vertices.buffer.contents().advanced(by: i * MemoryLayout<SIMD3<Float>>.stride)
            let modelVertex = vertexPointer.bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee
            
            // Transform to world space
            let worldVertex = anchor.transform * simd_float4(modelVertex, 1)
            let worldPosition = simd_make_float3(worldVertex)
            
            // Check distance from camera/focus point
            let distanceToCamera = distance(worldPosition, cameraPosition)
            
            // Store vertex and whether it's in range
            vertices.append(worldPosition)
            vertexInRange.append(distanceToCamera <= maxDistance)
        }
        
        // Extract edges from the mesh (using faces to determine edges)
        var edges = Set<Edge>()
        
        // Process each face to extract edges
        let faceCount = geometry.faces.count
        let faceIndices = geometry.faces.buffer.contents().bindMemory(to: Int32.self, capacity: faceCount * 3)
        
        for faceIndex in 0..<faceCount {
            let i0 = Int(faceIndices[faceIndex * 3])
            let i1 = Int(faceIndices[faceIndex * 3 + 1])
            let i2 = Int(faceIndices[faceIndex * 3 + 2])
            
            // Only consider edges where at least one vertex is in range
            if vertexInRange[i0] || vertexInRange[i1] || vertexInRange[i2] {
                // Add the three edges of this face
                edges.insert(Edge(a: min(i0, i1), b: max(i0, i1)))
                edges.insert(Edge(a: min(i1, i2), b: max(i1, i2)))
                edges.insert(Edge(a: min(i2, i0), b: max(i2, i0)))
            }
        }
        
        // Now create line entities for each edge
        var lineEntities: [Entity] = []
        
        for edge in edges {
            // Only create lines for edges where both vertices are in range
            // This prevents partial lines at the boundary of our range
            if vertexInRange[edge.a] && vertexInRange[edge.b] {
                let start = vertices[edge.a]
                let end = vertices[edge.b]
                
                // Create line entity
                if let lineEntity = createLineEntity(from: start, to: end) {
                    lineEntities.append(lineEntity)
                }
            }
        }
        
        return lineEntities
    }
    
    private func createLineEntity(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Entity? {
        // Calculate length of line
        let length = distance(start, end)
        
        // Skip very short lines (likely visualization artifacts)
        if length < 0.01 {
            return nil
        }
        
        // Create a thin cylinder for the line
        let mesh = MeshResource.generateCylinder(height: length, radius: lineThickness)
        
        // Create a white unlit material for better visibility
        var material = UnlitMaterial()
        material.color = .init(tint: lineColor)
        
        // Create the entity
        let lineEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Position and orient the line
        positionLineEntity(lineEntity, from: start, to: end)
        
        return lineEntity
    }
    
    private func positionLineEntity(_ entity: ModelEntity, from start: SIMD3<Float>, to end: SIMD3<Float>) {
        // Calculate center position
        let center = (start + end) * 0.5
        entity.position = center
        
        // Calculate direction vector
        let direction = normalize(end - start)
        
        // Default cylinder is oriented along Y-axis, so we need to rotate to match our line
        if direction != SIMD3<Float>(0, 1, 0) && direction != SIMD3<Float>(0, -1, 0) {
            let yAxis = SIMD3<Float>(0, 1, 0)
            let rotationAxis = normalize(cross(yAxis, direction))
            let rotationAngle = acos(dot(yAxis, direction))
            
            // Set orientation using quaternion
            if !rotationAxis.x.isNaN && !rotationAxis.y.isNaN && !rotationAxis.z.isNaN && !rotationAngle.isNaN {
                entity.orientation = simd_quatf(angle: rotationAngle, axis: rotationAxis)
            }
        } else if direction.y < 0 {
            // Special case for downward direction
            entity.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }
    }
    
    // Represents a unique edge between two vertices
    private struct Edge: Hashable {
        let a: Int
        let b: Int
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        if !meshAnchors.isEmpty {
            updateMeshVisualization()
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            .filter { self.meshAnchors.keys.contains($0.identifier) }
        
        if !meshAnchors.isEmpty {
            updateMeshVisualization()
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            if let entities = meshAnchors[anchor.identifier] {
                entities.forEach { $0.removeFromParent() }
                meshAnchors.removeValue(forKey: anchor.identifier)
            }
        }
    }
}
