//
//  ModelGestureHandler.swift
//  Surface Capture App
//

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
        guard let entity = modelEntity, !isPositionLocked else { return }
        
        let translation = sender.translation(in: sender.view)
        let delta = SIMD3<Float>(Float(translation.x / 1000.0), 0, Float(translation.y / 1000.0))
        entity.transform.translation += delta
        lastPanLocation = sender.location(in: sender.view)
        sender.setTranslation(.zero, in: sender.view)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
