//
//  ARPlaneCaptureViewController.swift
//  Surface Capture
//
//  Created by Ashley Davison on 03/01/2025.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

class ARPlaneCaptureViewController: UIViewController {
    private var arView: ARView!
    private var planeAnchors: [ARAnchor: ModelEntity] = [:]
    private var capturedPlaneModel: ModelEntity?
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
    }
    
    private func setupARView() {
        arView = ARView(frame: view.bounds)
        view.addSubview(arView)
        
        // Configure AR session for high-quality plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        // Enable scene reconstruction for better plane detection
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
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
    
    @objc private func handleTap(_ sender: UITapGestureRecognizer) {
        let location = sender.location(in: arView)
        
        // Perform precise raycast against detected planes
        let results = arView.raycast(
            from: location,
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        if let firstResult = results.first {
            placeCapturedPlane(at: firstResult)
        }
    }
    
    
    
    /*
    private func placeCapturedPlane(at raycastResult: ARRaycastResult) {
        guard let capturedPlaneModel = self.capturedPlaneModel else { return }
        
        // Create anchor at raycast hit point
        let anchor = ARAnchor(transform: raycastResult.worldTransform)
        arView.session.add(anchor: anchor)
        
        // Clone the model to preserve original
        let modelClone = capturedPlaneModel.clone(recursive: true)
        
        // Create anchor entity
        let anchorEntity = AnchorEntity(anchor: anchor)
        
        // Get the plane's normal vector from raycast transform
        let planeNormal = SIMD3<Float>(
            raycastResult.worldTransform.columns.2[0],
            raycastResult.worldTransform.columns.2[1],
            raycastResult.worldTransform.columns.2[2]
        )
        
        // Calculate rotation to align model with plane normal
        let modelForward = SIMD3<Float>(0, 0, 1) // Assuming model faces forward by default
        let rotationAxis = cross(modelForward, planeNormal)
        
        if length(rotationAxis) > .ulpOfOne { // Check if rotation axis is not too close to zero
            let rotationAngle = acos(dot(modelForward, planeNormal))
            let rotation = simd_quatf(angle: rotationAngle, axis: normalize(rotationAxis))
            modelClone.transform.rotation = rotation
        }
        
        // Ensure 1:1 scale
        modelClone.scale = .one
        
        // Offset slightly to prevent z-fighting
        modelClone.position.z += 0.001
        
        // Add model to anchor
        anchorEntity.addChild(modelClone)
        arView.scene.addAnchor(anchorEntity)
        planeAnchors[anchor] = modelClone
        
        // Add visual feedback
        //addPlacementEffect(at: anchorEntity.position(relativeTo: nil))
    }*/
    
    /*
    private func placeCapturedPlane(at raycastResult: ARRaycastResult) {
        guard let capturedPlaneModel = self.capturedPlaneModel else { return }
        
        // Create anchor at raycast hit point
        let anchor = ARAnchor(transform: raycastResult.worldTransform)
        arView.session.add(anchor: anchor)
        
        // Clone the model to preserve original
        let modelClone = capturedPlaneModel.clone(recursive: true)
        
        // Extract plane orientation from raycast result
        let planeNormal = SIMD3<Float>(
            raycastResult.worldTransform.columns.2.x,
            raycastResult.worldTransform.columns.2.y,
            raycastResult.worldTransform.columns.2.z
        )
        
        // Create anchor entity and set up transformation
        let anchorEntity = AnchorEntity(anchor: anchor)
        
        // Ensure 1:1 scale
        modelClone.scale = .one
        
        // Orient model to match plane
        modelClone.look(at: planeNormal, from: .zero, relativeTo: nil)
        
        // Offset slightly to prevent z-fighting
        modelClone.position.z += 0.001
        
        anchorEntity.addChild(modelClone)
        arView.scene.addAnchor(anchorEntity)
        planeAnchors[anchor] = modelClone
        
        // Add visual feedback
        //addPlacementEffect(at: anchorEntity.position(relativeTo: nil))
    }*/
    
    private func addPlacementEffect(at position: SIMD3<Float>) {
        // Create and add a particle system or visual effect
        // to show successful placement
        let box = ModelEntity(mesh: .generateBox(size: 0.1))
        box.model?.materials = [SimpleMaterial(color: .green, isMetallic: false)]
        
        let boxAnchor = AnchorEntity(world: position)
        boxAnchor.addChild(box)
        
        arView.scene.addAnchor(boxAnchor)
        
        // Animate the effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            boxAnchor.removeFromParent()
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
