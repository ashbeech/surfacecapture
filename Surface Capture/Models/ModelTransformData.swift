// ModelTransformData.swift

import Foundation
import simd

// Codable structure to transmit model entity transform data
struct ModelTransformData: Codable {
    // Basic transform properties
    var position: SIMD3<Float>
    var rotation: Quaternion
    var scale: SIMD3<Float>
    
    // Additional properties
    var isPulsing: Bool
    var opacity: Float
    var isVisible: Bool
    
    // Since SIMD types aren't directly Codable, we need a custom Quaternion type
    struct Quaternion: Codable {
        var x: Float
        var y: Float
        var z: Float
        var w: Float
        
        init(x: Float, y: Float, z: Float, w: Float) {
            self.x = x
            self.y = y
            self.z = z
            self.w = w
        }
        
        init(from simdQuat: simd_quatf) {
            self.x = simdQuat.vector.x
            self.y = simdQuat.vector.y
            self.z = simdQuat.vector.z
            self.w = simdQuat.vector.w
        }
        
        var simdQuaternion: simd_quatf {
            return simd_quatf(vector: SIMD4<Float>(x, y, z, w))
        }
    }
    
    // Constructor from model entity properties
    init(position: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>,
         isPulsing: Bool = false, opacity: Float = 1.0, isVisible: Bool = true) {
        self.position = position
        self.rotation = Quaternion(from: rotation)
        self.scale = scale
        self.isPulsing = isPulsing
        self.opacity = opacity
        self.isVisible = isVisible
    }
}
