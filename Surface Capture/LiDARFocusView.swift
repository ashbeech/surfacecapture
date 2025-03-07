//
//  LiDARFocusView.swift
//  Surface Capture App
//

/*
import SwiftUI
import RealityKit
import ARKit
import Combine
import MetalKit

@available(iOS 17.0, *)
struct LiDARFocusView: UIViewRepresentable {
    var session: ObjectCaptureSession
    @Binding var isEnabled: Bool
    var diameter: CGFloat = 150 // Diameter of the circular focus area
    
    func makeUIView(context: Context) -> MeshVisualizationView {
        let meshView = MeshVisualizationView(frame: .zero)
        
        // Configure the view
        meshView.preferredFramesPerSecond = 30
        meshView.isOpaque = false
        meshView.alpha = 0.9
        meshView.backgroundColor = .clear
        
        // Create the circular mask for the focus area
        setupCircularMask(for: meshView)
        
        // Connect the coordinator to handle AR updates
        meshView.arDelegate = context.coordinator
        context.coordinator.setupARSession(for: meshView)
        
        return meshView
    }
    
    func updateUIView(_ uiView: MeshVisualizationView, context: Context) {
        // Update visibility
        uiView.isHidden = !isEnabled
        
        // Update the circular mask if needed
        if let maskLayer = uiView.layer.mask as? CAShapeLayer {
            let center = CGPoint(x: uiView.bounds.midX, y: uiView.bounds.midY)
            maskLayer.path = UIBezierPath(arcCenter: center,
                                         radius: diameter / 2,
                                         startAngle: 0,
                                         endAngle: 2 * .pi,
                                         clockwise: true).cgPath
        }
        
        // Update properties for the Metal renderer
        context.coordinator.updateDepthVisualization(isEnabled: isEnabled)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func setupCircularMask(for view: UIView) {
        let maskLayer = CAShapeLayer()
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        maskLayer.path = UIBezierPath(arcCenter: center,
                                     radius: diameter / 2,
                                     startAngle: 0,
                                     endAngle: 2 * .pi,
                                     clockwise: true).cgPath
        view.layer.mask = maskLayer
        
        // Add observer for layout changes to update mask position
        NotificationCenter.default.addObserver(forName: UIView.didChangeNotification,
                                              object: view,
                                              queue: .main) { _ in
            if let maskLayer = view.layer.mask as? CAShapeLayer {
                let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
                maskLayer.path = UIBezierPath(arcCenter: center,
                                             radius: self.diameter / 2,
                                             startAngle: 0,
                                             endAngle: 2 * .pi,
                                             clockwise: true).cgPath
            }
        }
    }
    
    // Metal-based visualization view for better performance
    class MeshVisualizationView: MTKView {
        weak var arDelegate: ARSessionDelegate?
        var arSession: ARSession?
        var currentMeshAnchors: [ARMeshAnchor] = []
        
        override func layoutSubviews() {
            super.layoutSubviews()
            // Set device and configure layer
            if self.device == nil {
                self.device = MTLCreateSystemDefaultDevice()
                self.framebufferOnly = false
                
                // Configure for transparency
                self.layer.isOpaque = false
                self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            }
        }
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        private var parent: LiDARFocusView
        private var arSession: ARSession?
        private var displayLink: CADisplayLink?
        private var cancellables = Set<AnyCancellable>()
        private var lastUpdateTime: TimeInterval = 0
        private var isVisualizationEnabled = false
        
        init(_ parent: LiDARFocusView) {
            self.parent = parent
            super.init()
        }
        
        func setupARSession(for view: MeshVisualizationView) {
            // Create and configure the AR session
            let session = ARSession()
            session.delegate = self
            view.arSession = session
            self.arSession = session
            
            // Configure AR session for high-quality mesh reconstruction
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                let config = ARWorldTrackingConfiguration()
                config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
                config.sceneReconstruction = .mesh
                session.run(config)
            }
            
            // Set up display link for rendering
            displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
            displayLink?.preferredFramesPerSecond = 30
            displayLink?.add(to: .main, forMode: .common)
        }
        
        func updateDepthVisualization(isEnabled: Bool) {
            isVisualizationEnabled = isEnabled
        }
        
        @objc func updateFrame() {
            guard isVisualizationEnabled,
                  let session = arSession,
                  let frame = session.currentFrame,
                  let meshView = session.configuration?.viewportSize != nil ? session.view : nil,
                  let metalView = meshView as? MeshVisualizationView,
                  metalView.device != nil else { return }
            
            // Limit update rate
            let currentTime = CACurrentMediaTime()
            if currentTime - lastUpdateTime < 0.1 {
                return
            }
            lastUpdateTime = currentTime
            
            // Update Metal rendering
            updateMeshVisualization(in: metalView, frame: frame)
        }
        
        private func updateMeshVisualization(in view: MeshVisualizationView, frame: ARFrame) {
            // Get mesh anchors from the session
            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            
            // Only process if we have new meshes to display
            if meshAnchors != view.currentMeshAnchors {
                view.currentMeshAnchors = meshAnchors
                
                // Get camera position
                let cameraTransform = frame.camera.transform
                let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                                cameraTransform.columns.3.y,
                                                cameraTransform.columns.3.z)
                
                // Get camera forward direction
                let cameraForward = SIMD3<Float>(-cameraTransform.columns.2.x,
                                               -cameraTransform.columns.2.y,
                                               -cameraTransform.columns.2.z)
                
                // Filter meshes in front of camera
                let filteredMeshes = meshAnchors.filter { anchor in
                    let meshPosition = SIMD3<Float>(anchor.transform.columns.3.x,
                                                  anchor.transform.columns.3.y,
                                                  anchor.transform.columns.3.z)
                    let vectorToMesh = meshPosition - cameraPosition
                    let distance = simd_length(vectorToMesh)
                    let direction = simd_normalize(vectorToMesh)
                    let dotProduct = simd_dot(direction, cameraForward)
                    
                    // Only accept meshes in the direction the camera is facing and within range
                    return dotProduct > 0.7 && distance < 1.5
                }
                
                // Render meshes
                for mesh in filteredMeshes {
                    renderWireframeMesh(mesh: mesh.geometry, transform: mesh.transform, in: view, camera: frame.camera)
                }
            }
        }
        
        private func renderWireframeMesh(mesh: ARMeshGeometry, transform: simd_float4x4, in view: MTKView, camera: ARCamera) {
            guard let device = view.device else { return }
            
            // Create a simple wireframe material
            let material = SCNMaterial()
            material.fillMode = .lines
            material.diffuse.contents = UIColor(red: 0, green: 0.8, blue: 1.0, alpha: 0.7)
            material.isDoubleSided = true
            
            // Create a Metal command queue
            let commandQueue = device.makeCommandQueue()
            
            // Create a render pass descriptor
            guard let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            // Set up a basic pipeline state for wireframe rendering
            let library = device.makeDefaultLibrary()
            let vertexFunction = library?.makeFunction(name: "basicVertexShader")
            let fragmentFunction = library?.makeFunction(name: "basicFragmentShader")
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            
            do {
                let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                renderEncoder.setRenderPipelineState(pipelineState)
                
                // Set the transform matrices
                let modelMatrix = transform
                let viewMatrix = camera.viewMatrix(for: .portrait)
                let projectionMatrix = camera.projectionMatrix(for: .portrait,
                                                              viewportSize: view.drawableSize,
                                                              zNear: 0.001,
                                                              zFar: 1000)
                
                // Create a combined model-view-projection matrix
                let mvpMatrix = projectionMatrix * viewMatrix * modelMatrix
                
                // Set shader uniforms
                renderEncoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<simd_float4x4>.stride, index: 0)
                
                // End encoding and commit
                renderEncoder.endEncoding()
                commandBuffer.present(drawable)
                commandBuffer.commit()
                
            } catch {
                print("Failed to create pipeline state: \(error)")
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Process updates - needed for ARSessionDelegate
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // Handle mesh anchor additions
            let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            if !meshAnchors.isEmpty && isVisualizationEnabled {
                // Force an update of our visualization
                updateFrame()
            }
        }
        
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            // Handle mesh anchor updates
            let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
            if !meshAnchors.isEmpty && isVisualizationEnabled {
                // Force an update of our visualization
                updateFrame()
            }
        }
        
        deinit {
            displayLink?.invalidate()
            displayLink = nil
            
            arSession?.pause()
            arSession = nil
            
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }
    }
}

@available(iOS 17.0, *)
struct CircularLiDARFocusView: View {
    var session: ObjectCaptureSession
    @Binding var isEnabled: Bool
    var diameter: CGFloat = 150
    
    var body: some View {
        ZStack {
            if isEnabled {
                // Center LiDAR focus view with circular mask
                LiDARFocusView(session: session, isEnabled: $isEnabled, diameter: diameter)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    // Use transition for smooth appearance/disappearance
                    .transition(.opacity)
                
                // Add pulsing indicator to show active scanning
                Circle()
                    .stroke(Color.cyan.opacity(0.7), lineWidth: 2)
                    .frame(width: diameter + 6, height: diameter + 6)
                    .scaleEffect(isEnabled ? 1.1 : 1.0)
                    .opacity(isEnabled ? 0.7 : 0)
                    .animation(
                        Animation.easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true),
                        value: isEnabled
                    )
                
                // Add info text below the circle
                VStack {
                    Spacer()
                        .frame(height: diameter / 2 + 20)
                    
                    Text("LiDAR Depth Visualization")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isEnabled)
    }
}

// Extension to make the modifier easily applicable
@available(iOS 17.0, *)
extension View {
    func withLiDARFocus(session: ObjectCaptureSession, isEnabled: Binding<Bool>, diameter: CGFloat = 150) -> some View {
        self.modifier(LiDARFocusViewModifier(session: session, isEnabled: isEnabled, diameter: diameter))
    }
}

// Convenience view modifier to add LiDAR focus to any view containing an ObjectCaptureSession
@available(iOS 17.0, *)
struct LiDARFocusViewModifier: ViewModifier {
    var session: ObjectCaptureSession
    @Binding var isEnabled: Bool
    var diameter: CGFloat
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            // Add the circular LiDAR focus on top if enabled
            if isEnabled {
                CircularLiDARFocusView(session: session, isEnabled: $isEnabled, diameter: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }
}
*/
