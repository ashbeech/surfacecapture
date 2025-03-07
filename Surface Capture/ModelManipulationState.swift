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
    
    // Track 90-degree rotations separately
    private var rotationX90: Float = 0
    private var rotationY90: Float = 0
    private var rotationZ90: Float = 0
    
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
    
    // Track the current cumulative transformation
    private var currentTransform: simd_float4x4 = matrix_identity_float4x4
    
    // Add model entity reference
    private var modelEntity: ModelEntity?
    
    // Initialize the model entity reference and save initial transform
    func setModelEntity(_ entity: ModelEntity) {
        modelEntity = entity
        currentTransform = entity.transform.matrix
        currentRotation = entity.orientation
    }
    
    func startManipulation(_ state: ModelManipulationState) {
        // Save the current state before changing
        if currentState != .none {
            // Save current transform before switching modes
            saveCurrentTransform()
        }
        
        currentState = state
    }
        
    func endManipulation() {
        // Save the final transform when ending manipulation
        saveCurrentTransform()
        currentState = .none
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
        rotationX90 = 0
        rotationY90 = 0
        rotationZ90 = 0
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
        case .rotatingY:
            rotationY += delta
        case .rotatingZ:
            rotationZ += delta
        default:
            break
        }
        
        return updateCombinedRotation()
    }
    
    private func updateCombinedRotation() -> simd_quatf {
        // Combine fine-tuning rotations with 90-degree rotations
        let xRotation = simd_quatf(angle: rotationX + rotationX90, axis: [1, 0, 0])
        let yRotation = simd_quatf(angle: rotationY + rotationY90, axis: [0, 1, 0])
        let zRotation = simd_quatf(angle: rotationZ + rotationZ90, axis: [0, 0, 1])
        
        // Apply rotations in order: X, Y, Z
        return xRotation * yRotation * zRotation
    }
    
    func getCurrentRotation() -> simd_quatf {
        return currentRotation
    }
    
    // Add method to handle 90-degree rotations
    func rotate90Degrees(axis: ModelManipulationState) {
        let angle = Float.pi / 2 // 90 degrees
        
        switch axis {
        case .rotatingX:
            rotationX90 += angle
        case .rotatingY:
            rotationY90 += angle
        case .rotatingZ:
            rotationZ90 += angle
        default:
            return
        }
        
        // Apply combined rotation
        _ = updateCombinedRotation() // Fix unused result warning
    }
    
    func setCurrentRotation(_ rotation: simd_quatf) {
        currentRotation = rotation
        
        // Update the transform matrix to reflect this rotation
        if let modelEntity = modelEntity {
            // Create a new transform with the updated rotation
            var newTransform = currentTransform
            
            // Extract scale and position from current transform
            let position = SIMD3<Float>(currentTransform.columns.3.x,
                                       currentTransform.columns.3.y,
                                       currentTransform.columns.3.z)
            
            // Create rotation matrix
            let rotationMatrix = matrix_float4x4(rotation)
            
            // Update rotation component of transform
            newTransform.columns.0 = rotationMatrix.columns.0
            newTransform.columns.1 = rotationMatrix.columns.1
            newTransform.columns.2 = rotationMatrix.columns.2
            
            // Preserve position
            newTransform.columns.3 = SIMD4<Float>(position.x, position.y, position.z, 1.0)
            
            currentTransform = newTransform
        }
    }
    
    private func extractEulerAngles(from quaternion: simd_quatf) -> (Float, Float, Float) {
        // Break down the complex expression into smaller parts
        let qx = quaternion.vector.x
        let qy = quaternion.vector.y
        let qz = quaternion.vector.z
        let qw = quaternion.vector.w
        
        // Calculate x (pitch)
        let sinp = 2.0 * (qw * qx - qy * qz)
        let x = abs(sinp) >= 1 ? copysign(Float.pi / 2, sinp) : asin(sinp)
        
        // Calculate y (yaw)
        let siny_cosp = 2.0 * (qw * qy + qx * qz)
        let cosy_cosp = 1.0 - 2.0 * (qx * qx + qy * qy)
        let y = atan2(siny_cosp, cosy_cosp)
        
        // Calculate z (roll)
        let sinr_cosp = 2.0 * (qw * qz + qx * qy)
        let cosr_cosp = 1.0 - 2.0 * (qy * qy + qz * qz)
        let z = atan2(sinr_cosp, cosr_cosp)
        
        return (x, y, z)
    }
    
    // Save the current model transform
    func saveCurrentTransform() {
        guard let modelEntity = modelEntity else { return }
        currentTransform = modelEntity.transform.matrix
        
        // Update rotation tracking to match current orientation
        currentRotation = modelEntity.orientation
    }
    
    // Apply saved transform to the model
    func applyCurrentTransform() {
        guard let modelEntity = modelEntity else { return }
        
        // Extract components from the current transform matrix
        let position = SIMD3<Float>(currentTransform.columns.3.x,
                                   currentTransform.columns.3.y,
                                   currentTransform.columns.3.z)
        
        // Apply the saved transform
        modelEntity.position = position
        modelEntity.orientation = currentRotation
    }
}
