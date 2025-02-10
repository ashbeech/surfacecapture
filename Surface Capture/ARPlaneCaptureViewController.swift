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
    private var capturedPlaneModel: ModelEntity?
    private var cancellables = Set<AnyCancellable>()
    
    // Gesture tracking properties
    private var lastScale: CGFloat = 1.0
    private var lastRotation: Angle = .zero
    private var accumulatedRotation: Angle = .zero
    private var lastPanLocation: CGPoint = .zero
    private var activeModelEntity: ModelEntity?
    
    @Published var isModelSelected: Bool = false
    @Published var modelManipulator: ModelManipulator
    @Published var isPulsing: Bool = false
    
    override init(nibName nibNameOrNil: String? = nil, bundle nibBundleOrNil: Bundle? = nil) {
        self.modelManipulator = ModelManipulator()
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder: NSCoder) {
        self.modelManipulator = ModelManipulator()
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupGestures()
        setupModelManipulationGesture()
    }
    
    private func setupARView() {
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
        guard let modelEntity = capturedPlaneModel,
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
        guard let modelEntity = capturedPlaneModel,
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
        guard let modelEntity = capturedPlaneModel,
              modelManipulator.currentState == .none else { return }
        
        let translation = gesture.translation(in: gesture.view)
        let delta = SIMD3<Float>(Float(translation.x / 1000.0), 0, Float(translation.y / 1000.0))
        modelEntity.transform.translation += delta
        lastPanLocation = gesture.location(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    private var currentAnchor: AnchorEntity?
    
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
                    return
                }
            }
            
            // If we have a model and tapped on a plane (not the model), place it
            if let capturedPlaneModel = self.capturedPlaneModel,
               // Only place if we're not in selection mode
               let raycastResult = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                isModelSelected = false
                let newAnchor = AnchorEntity(world: raycastResult.worldTransform)
                capturedPlaneModel.position = [0, 0, 0]
                newAnchor.addChild(capturedPlaneModel)
                arView.scene.addAnchor(newAnchor)
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
    
    private var currentOpacity: Float = 1.0  // Add this to track current opacity
    
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
                
                // Initialize the opacity when loading
                currentOpacity = 1.0
                
                // Set initial transparency mode for all materials
                if let model = modelEntity.model {
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
