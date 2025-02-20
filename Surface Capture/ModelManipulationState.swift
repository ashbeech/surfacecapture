//
//  ModelManipulationState 2.swift
//  Surface Capture
//

import Foundation
import simd
import RealityKit

enum ModelManipulationState {
    case none
    case rotatingX
    case rotatingY
    case rotatingZ
    case adjustingDepth
}

class ModelManipulator: ObservableObject {
    @Published var currentState: ModelManipulationState = .none
    @Published var lastDragLocation: CGPoint?
    
    // Track current rotation quaternion
    private var currentRotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    
    // Track individual axis rotations in radians
    private var rotationX: Float = 0
    private var rotationY: Float = 0
    private var rotationZ: Float = 0
    
    // Add state tracking for each button
    @Published var isRotatingX: Bool = false
    @Published var isRotatingY: Bool = false
    @Published var isRotatingZ: Bool = false
    @Published var isAdjustingDepth: Bool = false
    var onStateChange: ((ModelManipulationState) -> Void)?
    
    // Track original position
    private var originalPosition: SIMD3<Float>?
    // Track original scale
    private var originalScale: SIMD3<Float>?
    
    
    func startManipulation(_ state: ModelManipulationState) {
        if currentState == state {
            currentState = .none
        } else {
            currentState = state
        }
        lastDragLocation = nil
        onStateChange?(currentState)  // Notify state change
    }
        
    func endManipulation() {
        currentState = .none
        lastDragLocation = nil
        onStateChange?(currentState)  // Notify state change
    }
    
    func setOriginalPosition(_ position: SIMD3<Float>) {
        originalPosition = position
    }
    
    // Add function to set original scale
    func setOriginalScale(_ scale: SIMD3<Float>) {
        originalScale = scale
    }
    
    func resetTransforms(_ entity: ModelEntity) {
        rotationX = 0
        rotationY = 0
        rotationZ = 0
        entity.transform.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        
        if let originalPosition = originalPosition {
            entity.position = originalPosition
        }
        
        // Reset scale to original value or default to 1 if not set
        if let originalScale = originalScale {
            entity.transform.scale = originalScale
        } else {
            entity.transform.scale = .one
        }
        
        // Reset all states
        endManipulation()
    }
    
    func updateRotation(delta: Float, for axis: ModelManipulationState) -> simd_quatf {
        switch axis {
        case .rotatingX:
            rotationX += delta
            let xRotation = simd_quatf(angle: rotationX, axis: [1, 0, 0])
            let yRotation = simd_quatf(angle: rotationY, axis: [0, 1, 0])
            let zRotation = simd_quatf(angle: rotationZ, axis: [0, 0, 1])
            return xRotation * yRotation * zRotation
            
        case .rotatingY:
            rotationY += delta
            let xRotation = simd_quatf(angle: rotationX, axis: [1, 0, 0])
            let yRotation = simd_quatf(angle: rotationY, axis: [0, 1, 0])
            let zRotation = simd_quatf(angle: rotationZ, axis: [0, 0, 1])
            return xRotation * yRotation * zRotation
            
        case .rotatingZ:
            rotationZ += delta
            let xRotation = simd_quatf(angle: rotationX, axis: [1, 0, 0])
            let yRotation = simd_quatf(angle: rotationY, axis: [0, 1, 0])
            let zRotation = simd_quatf(angle: rotationZ, axis: [0, 0, 1])
            return xRotation * yRotation * zRotation
            
        default:
            return currentRotation
        }
    }
    
    func getCurrentRotation() -> simd_quatf {
        let xRotation = simd_quatf(angle: rotationX, axis: [1, 0, 0])
        let yRotation = simd_quatf(angle: rotationY, axis: [0, 1, 0])
        let zRotation = simd_quatf(angle: rotationZ, axis: [0, 0, 1])
        return xRotation * yRotation * zRotation
    }
}
