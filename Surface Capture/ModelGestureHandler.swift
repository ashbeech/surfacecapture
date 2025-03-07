//
//  ModelGestureHandler.swift
//  Surface Capture App
//
/*
import SwiftUI
import RealityKit
import ARKit
import Combine

class ModelGestureHandler: NSObject, UIGestureRecognizerDelegate {
    private var lastScale: CGFloat = 1.0
    private var lastRotation: Angle = .zero
    private var accumulatedRotation: Angle = .zero
    private var lastPanLocation: CGPoint = .zero
    
    weak var modelEntity: ModelEntity?
    weak var arView: ARView?
    
    var isPositionLocked: Bool = false
    var isRotationLocked: Bool = false
    var isScaleLocked: Bool = false
    
    func setupGestures(for view: ARView, entity: ModelEntity) {
        self.arView = view
        self.modelEntity = entity
        
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation))
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        
        rotationGesture.delegate = self
        pinchGesture.delegate = self
        panGesture.delegate = self
        
        view.addGestureRecognizer(rotationGesture)
        view.addGestureRecognizer(pinchGesture)
        view.addGestureRecognizer(panGesture)
    }
    
    func removeGestures() {
        guard let arView = arView else { return }
        
        for gesture in arView.gestureRecognizers ?? [] {
            arView.removeGestureRecognizer(gesture)
        }
    }
    
    @objc func handleRotation(_ sender: UIRotationGestureRecognizer) {
        guard let entity = modelEntity, !isRotationLocked else { return }
        
        if sender.state == .began {
            lastRotation = .zero
        }
        
        let rotation = Angle(radians: Double(sender.rotation)) + accumulatedRotation
        entity.transform.rotation = simd_quatf(angle: Float(rotation.radians), axis: [0, -1, 0])
        lastRotation = rotation
        
        if sender.state == .ended {
            accumulatedRotation = rotation
        }
    }
    
    @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard let entity = modelEntity, !isScaleLocked else { return }
        
        if sender.state == .began {
            lastScale = 1.0
        }
        
        let scale = Float(sender.scale) / Float(lastScale)
        entity.transform.scale *= SIMD3<Float>(repeating: scale)
        lastScale = sender.scale
        
        if sender.state == .ended {
            lastScale = 1.0
        }
    }
    
    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard let entity = modelEntity, !isPositionLocked, let arView = sender.view as? ARView else { return }
        
        let translation = sender.translation(in: arView)
        
        // Get the camera's position and orientation
        guard let camera = arView.session.currentFrame?.camera else {
            sender.setTranslation(.zero, in: arView)
            return
        }
        
        // Calculate the right and up vectors in world space based on camera orientation
        let cameraTransform = camera.transform
        
        // Extract the right and up vectors from the camera transform matrix
        let cameraRight = SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)
        let cameraUp = SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)
        
        // Create movement delta based on camera orientation
        let deltaRight = cameraRight * Float(translation.x / 1000.0)
        let deltaUp = cameraUp * Float(-translation.y / 1000.0) // Negative because screen Y is inverted
        
        // Apply the combined delta
        let delta = deltaRight + deltaUp
        entity.transform.translation += delta
        
        // Reset the translation for continuous updates
        lastPanLocation = sender.location(in: arView)
        sender.setTranslation(.zero, in: arView)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
*/
