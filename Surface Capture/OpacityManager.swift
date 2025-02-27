//
//  OpacityManager.swift
//  Surface Capture App
//

import RealityKit
import Combine
import Foundation

struct OpacityComponent: Component {
    var baseOpacity: Float = 0.9
    var currentOpacity: Float = 0.9
    var isPulsing: Bool = false
    var texture: MaterialParameters.Texture? = nil
}

class OpacityManager {
    private static let minOpacity: Float = 0.09
    private static let maxOpacity: Float = 0.9
    private static let pulseDuration: TimeInterval = 3.33
    private static var pulseTimer: Timer?
    private static var increasing = true
    
    static func startPulsing(_ entity: ModelEntity) {
        // Stop any existing pulse
        pulseTimer?.invalidate()
        pulseTimer = nil
        
        // Initialize or get opacity component
        var opacityComponent = entity.components[OpacityComponent.self] ?? OpacityComponent()
        opacityComponent.isPulsing = true
        entity.components[OpacityComponent.self] = opacityComponent
        
        increasing = true
        
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { timer in
            guard var opacityComponent = entity.components[OpacityComponent.self] else {
                timer.invalidate()
                pulseTimer = nil
                return
            }
            
            let baseOpacity = opacityComponent.baseOpacity
            let range = (maxOpacity - minOpacity) * baseOpacity
            let step = range / Float(pulseDuration * 12)
            
            if increasing {
                opacityComponent.currentOpacity += step
                if opacityComponent.currentOpacity >= baseOpacity {
                    opacityComponent.currentOpacity = baseOpacity
                    increasing = false
                }
            } else {
                opacityComponent.currentOpacity -= step
                if opacityComponent.currentOpacity <= baseOpacity * minOpacity {
                    opacityComponent.currentOpacity = baseOpacity * minOpacity
                    increasing = true
                }
            }
            
            // Round to one decimal place
            opacityComponent.currentOpacity = opacityComponent.currentOpacity * 10 / 10
            
            entity.components[OpacityComponent.self] = opacityComponent
            
            // Update the model's opacity
            adjustOpacity(entity, to: opacityComponent.currentOpacity)
        }
    }
    
    static func stopPulsing(_ entity: ModelEntity) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        
        if var opacityComponent = entity.components[OpacityComponent.self] {
            opacityComponent.isPulsing = false
            entity.components[OpacityComponent.self] = opacityComponent
            adjustOpacity(entity, to: opacityComponent.currentOpacity)
        }
    }
    
    private static func adjustOpacity(_ entity: ModelEntity, to value: Float) {
        guard let model = entity.model else { return }
        
        let newMaterials: [RealityKit.Material] = model.materials.map { material in
            if var pbr = material as? PhysicallyBasedMaterial {
                pbr.blending = .transparent(opacity: .init(floatLiteral: value))
                return pbr
            } else if var unlit = material as? UnlitMaterial {
                unlit.blending = .transparent(opacity: .init(floatLiteral: Float(Double(value))))
                return unlit
            }
            return material
        }
        
        entity.model?.materials = newMaterials
    }
    
    static func adjustBaseOpacity(_ entity: ModelEntity, by amount: Float) {
        var opacityComponent = entity.components[OpacityComponent.self] ?? OpacityComponent()
        
        opacityComponent.baseOpacity = max(0.05, min(opacityComponent.baseOpacity + amount, 1.0))
        if !opacityComponent.isPulsing {
            opacityComponent.currentOpacity = opacityComponent.baseOpacity
        }
        
        entity.components[OpacityComponent.self] = opacityComponent
        adjustOpacity(entity, to: opacityComponent.currentOpacity)
    }
}
