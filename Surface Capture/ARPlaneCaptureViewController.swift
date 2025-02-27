//
//  ARPlaneCaptureViewController.swift
//  Surface Capture App
//

import SwiftUI
import RealityKit
import ARKit
import Combine

class ARPlaneCaptureViewController: UIViewController, ObservableObject {
    
    private var arView: ARView!
    private var planeAnchors: [ARAnchor: ModelEntity] = [:]
    private var currentAnchor: AnchorEntity?
    private var capturedPlaneModel: ModelEntity?
    private var cancellables = Set<AnyCancellable>()
    private var activeAnchors: Set<AnchorEntity> = []
    
    // Gesture tracking properties
    private var lastScale: CGFloat = 1.0
    private var lastRotation: Angle = .zero
    private var accumulatedRotation: Angle = .zero
    private var lastPanLocation: CGPoint = .zero
    private var currentOpacity: Float = 1.0
    private var activeModelEntity: ModelEntity?
    private var originalMaterials: [RealityKit.Material]?
    
    @Published var isModelPlaced: Bool = false
    @Published var isModelSelected: Bool = false
    @Published var modelManipulator: ModelManipulator
    @Published var isPulsing: Bool = false
    @Published var currentManipulationState: ModelManipulationState = .none
    
    @Published var lockedPosition: Bool = false
    @Published var lockedRotation: Bool = false
    @Published var lockedScale: Bool = false
    @Published var isWorkModeActive: Bool = false
    
    var mode: CaptureType = .objectCapture
    
    init(mode: CaptureType, entity: ModelEntity? = nil) {
        self.mode = mode
        self.modelManipulator = ModelManipulator()
        self.capturedPlaneModel = entity
        
        super.init(nibName: nil, bundle: nil)
        
        // Add observer for state changes
        modelManipulator.onStateChange = { [weak self] newState in
            DispatchQueue.main.async {
                self?.currentManipulationState = newState
                self?.objectWillChange.send()
            }
        }
    }
    
    // Default initializer falls back to object capture mode
    override init(nibName nibNameOrNil: String? = nil, bundle nibBundleOrNil: Bundle? = nil) {
        self.modelManipulator = ModelManipulator()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        // Add observer for state changes
        modelManipulator.onStateChange = { [weak self] newState in
            DispatchQueue.main.async {
                self?.currentManipulationState = newState
                self?.objectWillChange.send()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        self.modelManipulator = ModelManipulator()
        super.init(coder: coder)
    }
    
    deinit {
        print("ARPlaneCaptureViewController is being deinitialized")
        //cleanupSceneResources()
        //cleanup()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupGestures()
        setupModelManipulationGesture()
    }
    
    // Override view lifecycle methods
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        //cleanupSceneResources()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        arView?.session.pause()
    }
    /*
     private func cleanup() {
     
     }
     */
    /*
     func clearARScene() {
     // Reset all state
     isModelSelected = false
     isModelPlaced = false
     isPulsing = false
     lockedPosition = false
     lockedRotation = false
     lockedScale = false
     isWorkModeActive = false
     
     // Remove all subscriptions from ARView updates
     if let arView = arView {
     arView.scene.subscribe(to: SceneEvents.Update.self) { _ in }.cancel()
     }
     
     // Clean up model resources
     if let model = capturedPlaneModel {
     // Remove the model component entirely instead of trying to modify it
     model.components[ModelComponent.self] = nil
     
     // Remove collision components
     model.components[CollisionComponent.self] = nil
     
     // Remove model from parent
     model.removeFromParent()
     }
     
     // Clean up all active anchors
     activeAnchors.forEach { anchor in
     // Remove all child entities first
     anchor.children.forEach { entity in
     if let modelEntity = entity as? ModelEntity {
     // Remove model component
     modelEntity.components[ModelComponent.self] = nil
     modelEntity.components[CollisionComponent.self] = nil
     }
     entity.removeFromParent()
     }
     anchor.removeFromParent()
     }
     activeAnchors.removeAll()
     
     // Clean up current anchor
     if let currentAnchor = currentAnchor {
     currentAnchor.children.forEach { $0.removeFromParent() }
     currentAnchor.removeFromParent()
     self.currentAnchor = nil
     }
     
     // Clean up plane anchors
     planeAnchors.forEach { (arAnchor, entity) in
     entity.components[CollisionComponent.self] = nil
     entity.removeFromParent()
     }
     planeAnchors.removeAll()
     
     // Reset ARView scene
     if let arView = arView {
     // Remove all anchors from the scene
     arView.scene.anchors.removeAll()
     
     // Reset environment to a neutral state
     if let resource = try? EnvironmentResource.load(named: "white") {
     arView.environment.lighting.resource = resource
     }
     
     // Clear debug options
     arView.debugOptions = []
     
     // Remove coaching overlay if present
     arView.subviews.forEach { view in
     if view is ARCoachingOverlayView {
     view.removeFromSuperview()
     }
     }
     }
     
     // Clean up AR resources
     cleanup()
     }
     */
    func clearARScene() {
        // Reset all state
        isModelSelected = false
        isModelPlaced = false
        isPulsing = false
        lockedPosition = false
        lockedRotation = false
        lockedScale = false
        isWorkModeActive = false
        
        // Stop AR session and remove all anchors
        arView?.session.pause()
        
        // Remove all subscriptions from ARView updates
        if let arView = arView {
            arView.scene.subscribe(to: SceneEvents.Update.self) { _ in }.cancel()
        }
        
        // Remove all gestures to prevent retain cycles
        if let gestureRecognizers = arView?.gestureRecognizers {
            for recognizer in gestureRecognizers {
                arView?.removeGestureRecognizer(recognizer)
            }
        }
        
        // Clean up model resources - different handling for image plane vs 3D model
        if let model = capturedPlaneModel {
            // Stop any active pulsing
            if isPulsing {
                OpacityManager.stopPulsing(model)
                isPulsing = false
            }
            
            // Remove the model component entirely
            model.components[ModelComponent.self] = nil
            
            // Remove collision components
            model.components[CollisionComponent.self] = nil
            
            // Remove model from parent
            model.removeFromParent()
            
            // Important: Release the captured model reference completely
            capturedPlaneModel = nil
        }
        
        // Remove all anchors from the scene
        arView?.scene.anchors.removeAll()
        
        // Clean up all active anchors
        activeAnchors.forEach { anchor in
            anchor.children.forEach { entity in
                entity.removeFromParent()
            }
            anchor.removeFromParent()
        }
        activeAnchors.removeAll()
        
        // Clean up current anchor
        if let currentAnchor = currentAnchor {
            currentAnchor.children.forEach { $0.removeFromParent() }
            currentAnchor.removeFromParent()
            self.currentAnchor = nil
        }
        
        // Clean up outline entity if it exists
        if outlineEntity != nil {
            outlineEntity?.removeFromParent()
            outlineEntity = nil
        }
        
        // Cancel all subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // Reset model manipulator state
        modelManipulator.endManipulation()
    }
    
    private func setupARView() {
        
        print("****** AR VIEW TIME ******")
        
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        // Disable all lighting and visual effects
        arView.renderOptions = [
            .disableCameraGrain,
            .disableMotionBlur,
            .disableDepthOfField,
            .disableFaceMesh,
            .disablePersonOcclusion,
            .disableGroundingShadows,
            .disableAREnvironmentLighting,
            .disableHDR
        ]
        
        // Configure AR session for high-quality plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        // Enable scene reconstruction for better plane detection
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        // Set up bright, consistent lighting using the white skybox
        if let resource = try? EnvironmentResource.load(named: "white.skybox") {
            arView.environment.lighting.resource = resource
            arView.environment.lighting.intensityExponent = 1
        }
        arView.session.run(config)
        
        // Add tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        arView.addGestureRecognizer(tapGesture)
        
        // Set up coaching overlay
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.frame = arView.bounds
        arView.addSubview(coachingOverlay)
        
        // Track newly added anchors
        arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            guard let self = self else { return }
            // Update active anchors set from current scene anchors
            let currentAnchors = Set(self.arView.scene.anchors.compactMap { $0 as? AnchorEntity })
            self.activeAnchors = currentAnchors
        }.store(in: &cancellables)
        
        // Add debug visualization for planes
        arView.debugOptions = [.showSceneUnderstanding]
    }
    
    private func setupGestures() {
        // Rotation gesture
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation))
        rotationGesture.delegate = self
        arView.addGestureRecognizer(rotationGesture)
        
        // Pinch gesture for scaling
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinchGesture.delegate = self
        arView.addGestureRecognizer(pinchGesture)
        
        // Pan gesture for movement
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        arView.addGestureRecognizer(panGesture)
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        guard !lockedRotation, let modelEntity = capturedPlaneModel,
              modelManipulator.currentState == .none else { return }
        
        if gesture.state == .began {
            lastRotation = .zero
        }
        
        let rotation = Angle(radians: Double(gesture.rotation)) + accumulatedRotation
        modelEntity.transform.rotation = simd_quatf(angle: Float(rotation.radians), axis: [0, -1, 0])
        lastRotation = rotation
        
        if gesture.state == .ended {
            accumulatedRotation = rotation
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !lockedScale, let modelEntity = capturedPlaneModel,
              modelManipulator.currentState == .none else { return }
        
        if gesture.state == .began {
            lastScale = 1.0
        }
        
        let scale = Float(gesture.scale) / Float(lastScale)
        modelEntity.transform.scale *= SIMD3<Float>(repeating: scale)
        lastScale = gesture.scale
        
        if gesture.state == .ended {
            lastScale = 1.0
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !lockedPosition, let modelEntity = capturedPlaneModel,
              modelManipulator.currentState == .none else { return }
        
        let translation = gesture.translation(in: gesture.view)
        let delta = SIMD3<Float>(Float(translation.x / 1000.0), 0, Float(translation.y / 1000.0))
        modelEntity.transform.translation += delta
        lastPanLocation = gesture.location(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    private var outlineEntity: ModelEntity?
    private var modelTransformObserver: Cancellable?
    private var originalModelScale: SIMD3<Float>?
    
    internal func updateModelHighlight(isSelected: Bool) {
        guard let capturedPlaneModel = capturedPlaneModel else { return }
        
        if isSelected {
            if outlineEntity == nil {
                // Store original model scale when first creating the outline
                originalModelScale = capturedPlaneModel.scale
                
                // Get the visual bounds in model's space
                let bounds = capturedPlaneModel.visualBounds(relativeTo: capturedPlaneModel.parent)
                
                // Create an empty parent entity to handle positioning correctly
                let containerEntity = ModelEntity()
                outlineEntity = containerEntity
                
                // Add the container to the same parent as the model
                if let parentEntity = capturedPlaneModel.parent {
                    parentEntity.addChild(containerEntity)
                    containerEntity.position = capturedPlaneModel.position
                    containerEntity.orientation = capturedPlaneModel.orientation
                } else {
                    capturedPlaneModel.addChild(containerEntity)
                    containerEntity.position = .zero
                }
                
                // Create the actual wireframe box
                let boxSize = bounds.extents * 1.02  // 2% larger than model
                let boxEntity = createWireframeBox(size: boxSize, color: .white)
                
                // Position the box at the center of the bounds relative to the container
                containerEntity.addChild(boxEntity)
                
                // Determine center offset (if any)
                let centerOffset = bounds.center - capturedPlaneModel.position
                boxEntity.position = centerOffset
                
                // Set up subscription to model's transform changes
                modelTransformObserver = capturedPlaneModel.scene?.subscribe(to: SceneEvents.Update.self, { [weak self] _ in
                    self?.updateOutlineTransform()
                })
                
                // Initial transform update
                updateOutlineTransform()
            }
        } else {
            // Remove wireframe when deselected
            outlineEntity?.removeFromParent()
            outlineEntity = nil
            originalModelScale = nil
            
            // Remove transform observer
            modelTransformObserver?.cancel()
            modelTransformObserver = nil
        }
    }
    
    struct LineSegmentComponent: Component {
        static let query = EntityQuery(where: .has(LineSegmentComponent.self))
    }
    
    private func updateOutlineTransform() {
        guard let capturedPlaneModel = capturedPlaneModel,
              let containerEntity = outlineEntity,
              let originalScale = originalModelScale else { return }
        
        // Update container position and orientation to match model's current transform
        containerEntity.position = capturedPlaneModel.position
        containerEntity.orientation = capturedPlaneModel.orientation
        
        // Calculate relative scale - how much has the model scaled since we created the outline
        let relativeScale = SIMD3<Float>(
            capturedPlaneModel.scale.x / originalScale.x,
            capturedPlaneModel.scale.y / originalScale.y,
            capturedPlaneModel.scale.z / originalScale.z
        )
        
        // Apply relative scale to maintain proper proportions of the outline box
        containerEntity.scale = relativeScale
        
        // Compensate line thickness to maintain consistent visual appearance
        compensateLineThickness(containerEntity, relativeScale: relativeScale)
    }
    
    private func compensateLineThickness(_ entity: Entity, relativeScale: SIMD3<Float>) {
        // Calculate the average scale factor to determine how much to compensate
        let avgScale = (relativeScale.x + relativeScale.y + relativeScale.z) / 3.0
        
        for child in entity.children {
            if let modelEntity = child as? ModelEntity,
               modelEntity.components[LineSegmentComponent.self] != nil {
                // This is one of our line segments
                // Apply inverse scale to the x and z axes (radius dimensions) to keep thickness consistent
                let inverseScale = 1.0 / avgScale
                modelEntity.scale = SIMD3<Float>(inverseScale, 1.0, inverseScale)
            } else {
                // Recursively process children
                compensateLineThickness(child, relativeScale: relativeScale)
            }
        }
    }
    
    // Create a custom wireframe box using line segments with gaps in the middle
    private func createWireframeBox(size: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let halfWidth = size.x / 2
        let halfHeight = size.y / 2
        let halfLength = size.z / 2
        
        // Define the 8 corners of the box
        let corners: [SIMD3<Float>] = [
            // Bottom face
            [-halfWidth, -halfHeight, -halfLength],
            [halfWidth, -halfHeight, -halfLength],
            [halfWidth, -halfHeight, halfLength],
            [-halfWidth, -halfHeight, halfLength],
            // Top face
            [-halfWidth, halfHeight, -halfLength],
            [halfWidth, halfHeight, -halfLength],
            [halfWidth, halfHeight, halfLength],
            [-halfWidth, halfHeight, halfLength]
        ]
        
        // Define the 12 edges of the box (pairs of corner indices)
        let edges: [(Int, Int)] = [
            // Bottom face
            (0, 1), (1, 2), (2, 3), (3, 0),
            // Top face
            (4, 5), (5, 6), (6, 7), (7, 4),
            // Connecting edges
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        
        // Create a parent entity for all the lines
        let boxEntity = ModelEntity()
        
        // Create corner line segments (10% from each end of the edges)
        for (start, end) in edges {
            let startPoint = corners[start]
            let endPoint = corners[end]
            
            // Calculate the full edge vector
            let edgeVector = endPoint - startPoint
            let fullLength = length(edgeVector)
            let direction = normalize(edgeVector)
            
            // Calculate visible segment length (10% of full length)
            let visibleLength = fullLength * 0.1
            
            // 25% thicker than the original 0.001 radius
            let lineRadius: Float = 0.00125
            
            // Create the first corner segment (start to 10%)
            let firstSegmentEnd = startPoint + direction * visibleLength
            createLineSegment(from: startPoint, to: firstSegmentEnd, radius: lineRadius, color: color, parent: boxEntity)
            
            // Create the second corner segment (90% to end)
            let secondSegmentStart = endPoint - direction * visibleLength
            createLineSegment(from: secondSegmentStart, to: endPoint, radius: lineRadius, color: color, parent: boxEntity)
        }
        
        return boxEntity
    }
    
    // Helper function to create a single line segment
    private func createLineSegment(from startPoint: SIMD3<Float>, to endPoint: SIMD3<Float>, radius: Float, color: UIColor, parent: ModelEntity) {
        // Calculate line length
        let segmentLength = distance(startPoint, endPoint)
        
        // Create a thin cylinder for the line segment
        let lineMesh = MeshResource.generateCylinder(height: segmentLength, radius: radius)
        
        // Create material for the line
        var lineMaterial = UnlitMaterial()
        lineMaterial.color = .init(tint: color)
        
        // Create the line entity
        let lineEntity = ModelEntity(mesh: lineMesh, materials: [lineMaterial])
        
        // Add our custom component to identify this as a line segment
        lineEntity.components[LineSegmentComponent.self] = LineSegmentComponent()
        
        // Position and orient the line correctly
        positionLine(lineEntity, from: startPoint, to: endPoint)
        
        // Add the line to the parent entity
        parent.addChild(lineEntity)
    }
    
    // Position and orient a line entity between two points
    private func positionLine(_ lineEntity: ModelEntity, from startPoint: SIMD3<Float>, to endPoint: SIMD3<Float>) {
        // Calculate center position and direction
        let centerPosition = (startPoint + endPoint) / 2
        let direction = normalize(endPoint - startPoint)
        
        // Set position to the center
        lineEntity.position = centerPosition
        
        // Align cylinder with the direction vector
        // Default cylinder is aligned with y-axis, so we need to rotate
        if direction != SIMD3<Float>(0, 1, 0) && direction != SIMD3<Float>(0, -1, 0) {
            // For any other direction, we need to find the rotation axis
            // that rotates (0,1,0) to our direction
            let yAxis = SIMD3<Float>(0, 1, 0)
            let rotationAxis = normalize(cross(yAxis, direction))
            let rotationAngle = acos(dot(yAxis, direction))
            
            // Set the orientation using the rotation axis and angle
            if !rotationAxis.x.isNaN && !rotationAxis.y.isNaN && !rotationAxis.z.isNaN && !rotationAngle.isNaN {
                lineEntity.orientation = simd_quatf(angle: rotationAngle, axis: rotationAxis)
            }
        } else if direction.y < 0 {
            // Special case: direction is (0,-1,0)
            lineEntity.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        
        guard let capturedPlaneModel = self.capturedPlaneModel,
              modelManipulator.currentState == .none else { return }
        
        if let arView = sender.view as? ARView {
            let location = sender.location(in: arView)
            
            // Check if we tapped on the model
            if let result = arView.entity(at: location) {
                if result == capturedPlaneModel {
                    print("TAPPED ON MODEL")
                    isModelSelected = true
                    updateModelHighlight(isSelected: true)
                    return
                }
            }
            
            // If we have a model and tapped on a plane (not the model), place it
            if let capturedPlaneModel = self.capturedPlaneModel, !lockedPosition,
               // Only place if we're not in selection mode
               let raycastResult = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                isModelSelected = false
                updateModelHighlight(isSelected: false)
                isModelPlaced = true
                
                // Remove previous anchor if it exists
                if let oldAnchor = currentAnchor {
                    oldAnchor.removeFromParent()
                    activeAnchors.remove(oldAnchor)
                }
                
                let newAnchor = AnchorEntity(world: raycastResult.worldTransform)
                capturedPlaneModel.position = [0, 0, 0]
                newAnchor.addChild(capturedPlaneModel)
                arView.scene.addAnchor(newAnchor)
                currentAnchor = newAnchor
                activeAnchors.insert(newAnchor)
            }
        }
        /*
         if let arView = sender.view as? ARView {
         let tapLocation = sender.location(in: arView)
         if let raycastResult = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any).first {
         let newAnchor = AnchorEntity(world: raycastResult.worldTransform)
         capturedPlaneModel.position = [0, 0, 0]
         newAnchor.addChild(capturedPlaneModel)
         arView.scene.addAnchor(newAnchor)
         }
         }
         */
        
    }
    
    @objc internal func increaseOpacity() {
        print("====== INCREASE OPACITY ======")
        currentOpacity = min(currentOpacity + 0.15, 1.0)
        adjustOpacity(to: currentOpacity)
    }
    
    @objc internal func decreaseOpacity() {
        print("====== DECREASE OPACITY ======")
        currentOpacity = max(currentOpacity - 0.15, 0.05)
        adjustOpacity(to: currentOpacity)
    }
    
    private func adjustOpacity(to value: Float) {
        print("ADJUSTING OPACITY TO: \(value)")
        guard let capturedPlaneModel = self.capturedPlaneModel else {
            print("No captured model found")
            return
        }
        
        // Get all materials from the model
        guard let model = capturedPlaneModel.model else { return }
        
        // Create new materials array with updated opacity
        let newMaterials: [RealityKit.Material] = model.materials.map { material in
            if var pbr = material as? PhysicallyBasedMaterial {
                // Set the blending mode with new opacity
                pbr.blending = .transparent(opacity: .init(floatLiteral: value))
                return pbr
            } else if var unlit = material as? UnlitMaterial {
                unlit.blending = .transparent(opacity: .init(floatLiteral: Float(Double(value))))
                return unlit
            }
            return material
        }
        
        // Apply the new materials
        capturedPlaneModel.model?.materials = newMaterials
        
        print("Opacity updated")
    }
    
    func togglePulsing() {
        print("TOGGLE PULSING")
        
        isPulsing.toggle()
        if let capturedPlaneModel = capturedPlaneModel {
            if isPulsing {
                print("START PULSING")
                
                OpacityManager.startPulsing(capturedPlaneModel)
            } else {
                print("STOP PULSING")
                
                OpacityManager.stopPulsing(capturedPlaneModel)
            }
        }
    }
    
    @objc func handleModelManipulation(_ gesture: UIPanGestureRecognizer) {
        guard let modelEntity = capturedPlaneModel, isModelSelected else { return }
        
        let location = gesture.location(in: arView)
        
        switch gesture.state {
        case .began:
            modelManipulator.lastDragLocation = location
            
        case .changed:
            guard let lastLocation = modelManipulator.lastDragLocation else { return }
            
            let deltaY = Float(location.y - lastLocation.y)
            let deltaX = Float(location.x - lastLocation.x)
            
            switch modelManipulator.currentState {
            case .rotatingX:
                let rotation = deltaY * 0.01
                let newRotation = modelManipulator.updateRotation(delta: rotation, for: .rotatingX)
                modelEntity.transform.rotation = newRotation
                
            case .rotatingY:
                let rotation = deltaX * 0.01
                let newRotation = modelManipulator.updateRotation(delta: rotation, for: .rotatingY)
                modelEntity.transform.rotation = newRotation
                
            case .rotatingZ:
                let rotation = deltaY * 0.01
                let newRotation = modelManipulator.updateRotation(delta: rotation, for: .rotatingZ)
                modelEntity.transform.rotation = newRotation
                
            case .adjustingDepth:
                let depthDelta = deltaY * 0.001
                var currentPosition = modelEntity.position
                currentPosition.y += depthDelta
                modelEntity.position = currentPosition
                
            default:
                break
            }
            
            modelManipulator.lastDragLocation = location
            
        case .ended:
            modelManipulator.lastDragLocation = nil
            
        default:
            break
        }
        
        gesture.setTranslation(.zero, in: arView)
    }
    
    func setupModelManipulationGesture() {
        let manipulationGesture = UIPanGestureRecognizer(target: self, action: #selector(handleModelManipulation))
        manipulationGesture.delegate = self
        arView.addGestureRecognizer(manipulationGesture)
    }
    
    // Call this when setting up the view controller
    func setupModelManipulator() {
        modelManipulator = ModelManipulator()
        setupModelManipulationGesture()
    }
    
    func resetModelTransforms() {
        guard let modelEntity = capturedPlaneModel else { return }
        modelManipulator.resetTransforms(modelEntity)
        isPulsing = false
        OpacityManager.stopPulsing(modelEntity)
        // Reset selection state and outline
        isModelSelected = false
        outlineEntity?.removeFromParent()
        outlineEntity = nil
    }
    
    
    func loadCapturedModel(_ modelURL: URL) {
        print("Starting to load model from URL: \(modelURL)")
        Task {
            do {
                // Create required texture directories before loading model
                let snapshotFolder = modelURL.deletingLastPathComponent()
                    .appendingPathComponent("Snapshots")
                if let snapshotID = try? FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)
                    .first(where: { $0.hasDirectoryPath })?.lastPathComponent {
                    print("Found snapshot ID: \(snapshotID)")
                    try? FileManager.default.createDirectory(at: snapshotFolder.appendingPathComponent(snapshotID).appendingPathComponent("0"),
                                                             withIntermediateDirectories: true)
                }
                
                // Load the model with resolved textures
                let modelEntity = try await ModelEntity(contentsOf: modelURL)
                print("Model loaded successfully, converting to UnlitMaterial")
                modelEntity.scale = .one
                
                modelEntity.generateCollisionShapes(recursive: true)
                modelEntity.collision = CollisionComponent(shapes: modelEntity.collision?.shapes ?? [])
                
                // Store the original position when first loading the model
                modelManipulator.setOriginalPosition(modelEntity.position)
                modelManipulator.setOriginalScale(modelEntity.transform.scale)
                
                // Initialize the opacity when loading
                currentOpacity = 1.0
                
                // Set initial transparency mode for all materials
                if let model = modelEntity.model {
                    
                    originalMaterials = model.materials
                    
                    let initialMaterials: [RealityKit.Material] = model.materials.map { material in
                        if var pbr = material as? PhysicallyBasedMaterial {
                            pbr.blending = .transparent(opacity: .init(floatLiteral: 1.0))
                            return pbr
                        }
                        return material
                    }
                    modelEntity.model?.materials = initialMaterials
                }
                
                self.capturedPlaneModel = modelEntity
                print("Model assigned to capturedPlaneModel")
                
                showToast(message: "Model loaded successfully")
            } catch {
                print("Failed to load model: \(error)")
                showToast(message: "Failed to load model")
            }
        }
    }
    
    func pauseARSession() {
        arView?.session.pause()
    }
    
    private func extractSnapshotID(from url: URL) throws -> String? {
        let modelFolder = url.deletingLastPathComponent()
        let snapshotsFolder = modelFolder.appendingPathComponent("Snapshots")
        
        let contents = try FileManager.default.contentsOfDirectory(at: snapshotsFolder, includingPropertiesForKeys: nil)
        return contents.first { url in
            let folderName = url.lastPathComponent
            return folderName.count == 36 && folderName.contains("-")
        }?.lastPathComponent
    }
    
    private func showToast(message: String) {
        let toast = UILabel()
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.textColor = .white
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 14)
        toast.text = message
        toast.alpha = 0
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.numberOfLines = 0
        
        view.addSubview(toast)
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            toast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            toast.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
            toast.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.5, delay: 1.5, options: .curveEaseInOut, animations: {
                toast.alpha = 0
            }, completion: { _ in
                toast.removeFromSuperview()
            })
        })
    }
    
}

extension ARPlaneCaptureViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
