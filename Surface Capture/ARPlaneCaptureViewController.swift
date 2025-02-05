//
//  ARPlaneCaptureViewController.swift
//  Surface Capture App
//

import SwiftUI
import RealityKit
import ARKit
import Combine

class ARPlaneCaptureViewController: UIViewController {
    @MainActor private var appModel: AppDataModel?
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
        setupGestures()
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
        guard let modelEntity = activeModelEntity ?? capturedPlaneModel else { return }
        
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
        //guard let modelEntity = activeModelEntity ?? capturedPlaneModel else { return }
        guard let modelEntity = appModel?.selectedEntity else { return }
        
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
        //guard let modelEntity = activeModelEntity ?? capturedPlaneModel else { return }
        guard let modelEntity = appModel?.selectedEntity else { return }
        
        let translation = gesture.translation(in: gesture.view)
        let delta = SIMD3<Float>(Float(translation.x / 1000.0), 0, Float(translation.y / 1000.0))
        modelEntity.transform.translation += delta
        lastPanLocation = gesture.location(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        
        //guard let capturedPlaneModel = self.capturedPlaneModel else { return }
        guard let modelEntity = appModel?.selectedEntity else { return }
        
        if let arView = sender.view as? ARView {
            let tapLocation = sender.location(in: arView)
            if let raycastResult = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any).first {
                let newAnchor = AnchorEntity(world: raycastResult.worldTransform)
                modelEntity.position = [0, 0, 0]
                newAnchor.addChild(modelEntity)
                arView.scene.addAnchor(newAnchor)
            }
        }
        
    }
    
    func loadCapturedModel(_ modelURL: URL) {
        Task {
            do {
                // Create required texture directories before loading model
                let snapshotFolder = modelURL.deletingLastPathComponent()
                    .appendingPathComponent("Snapshots")
                if let snapshotID = try? FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)
                    .first(where: { $0.hasDirectoryPath })?.lastPathComponent {
                    try? FileManager.default.createDirectory(at: snapshotFolder.appendingPathComponent(snapshotID).appendingPathComponent("0"),
                                                          withIntermediateDirectories: true)
                }
                
                // First ensure textures are in correct locations
                if let snapshotID = try? extractSnapshotID(from: modelURL) {
                    let snapshotFolder = modelURL.deletingLastPathComponent()
                        .appendingPathComponent("Snapshots")
                        .appendingPathComponent(snapshotID)
                    
                    let meshFiles = try FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)
                        .filter { $0.pathExtension == "usdc" }
                    
                    for meshFile in meshFiles {
                        try USDAssetResolver.resolveTexturePaths(in: meshFile)
                        try USDAssetResolver.moveTexturesToExpectedLocation(from: meshFile)
                    }
                }
                
                // Load the model with resolved textures
                let modelEntity = try await ModelEntity(contentsOf: modelURL)
                modelEntity.scale = .one
                self.capturedPlaneModel = modelEntity
                
                /*
                if let appModel = (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.view.window?.windowScene?.keyWindow?.rootViewController?.view.subviews.first?.next as? UIHostingController<ContentView> {
                                            await MainActor.run {
                                                appModel.rootView.appModel.selectedEntity = modelEntity
                                            }
                                        }
                 */
                
                await MainActor.run {
                    self.appModel?.selectedEntity = modelEntity
                }
                
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
