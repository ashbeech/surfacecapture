//
//  ImagePlaneEntity.swift
//  Surface Capture
//

import RealityKit
import UIKit
import Combine

class ImagePlaneEntity {
    
    static func create(from image: UIImage, width: Float = 1.0) -> ModelEntity {
        // Calculate aspect ratio
        let aspectRatio = Float(image.size.width / image.size.height)
        let planeWidth = width
        let planeHeight = planeWidth / aspectRatio
        
        // Create plane mesh
        let mesh = MeshResource.generatePlane(width: planeWidth, depth: planeHeight)
        
        // Create a placeholder material initially
        var material = UnlitMaterial()
        // Use a visible alpha that will be noticeable
        let initialAlpha: CGFloat = 0.9
        material.color = .init(tint: .white.withAlphaComponent(initialAlpha))
        
        // Create entity
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        // Add opacity component (important to do this before changing the texture)
        var opacityComponent = OpacityComponent()
        opacityComponent.baseOpacity = Float(initialAlpha)
        opacityComponent.currentOpacity = Float(initialAlpha)
        entity.components[OpacityComponent.self] = opacityComponent
        
        // Save and apply texture
        saveImageToTemporaryFile(image) { url in
            guard let imageURL = url else { return }
            
            do {
                let texture = try TextureResource.load(contentsOf: imageURL)
                
                // Important: Get the current opacity to preserve it
                let opacity: Float
                //if let component = entity.components[OpacityComponent.self] as? OpacityComponent {
                if let component = entity.components[OpacityComponent.self] {
                    opacity = component.currentOpacity
                } else {
                    opacity = Float(initialAlpha)
                }
                
                // Create material with texture and correct alpha
                var updatedMaterial = UnlitMaterial()
                updatedMaterial.color = .init(
                    tint: .white.withAlphaComponent(CGFloat(opacity)),
                    texture: .init(texture)
                )
                
                // Set material with proper blending mode
                updatedMaterial.blending = .transparent(opacity: .init(floatLiteral: Float(Double(opacity))))
                
                // Apply the material
                entity.model?.materials = [updatedMaterial]
                
            } catch {
                print("Error loading texture: \(error)")
            }
        }
        
        // Add collision for interaction
        entity.generateCollisionShapes(recursive: true)
        
        return entity
    }
    
    static func updateTexture(_ entity: ModelEntity, with image: UIImage) {
        // Calculate new aspect ratio
        let aspectRatio = Float(image.size.width / image.size.height)
        let planeWidth: Float = 1.0
        let planeHeight = planeWidth / aspectRatio
        
        // Update mesh to match new image proportions
        let newMesh = MeshResource.generatePlane(width: planeWidth, depth: planeHeight)
        entity.model?.mesh = newMesh
        
        // Save and apply new texture
        saveImageToTemporaryFile(image) { url in
            guard let imageURL = url else { return }
            
            do {
                let texture = try TextureResource.load(contentsOf: imageURL)
                
                // Preserve current opacity
                let currentOpacity: Float
                //if let component = entity.components[OpacityComponent.self] as? OpacityComponent {
                if let component = entity.components[OpacityComponent.self] {
                    currentOpacity = component.currentOpacity
                } else {
                    currentOpacity = 0.1
                }
                
                // Create new material with updated texture
                var updatedMaterial = UnlitMaterial()
                updatedMaterial.color = .init(
                    tint: .white.withAlphaComponent(CGFloat(currentOpacity)),
                    texture: .init(texture)
                )
                
                // Apply new material
                entity.model?.materials = [updatedMaterial]
                
            } catch {
                print("Error updating texture: \(error)")
            }
        }
    }
    
    private static func saveImageToTemporaryFile(_ image: UIImage, completion: @escaping (URL?) -> Void) {
        DispatchQueue.global().async {
            do {
                let temporaryDirectoryURL = FileManager.default.temporaryDirectory
                let fileURL = temporaryDirectoryURL.appendingPathComponent("tempImage_\(UUID().uuidString).png")
                
                if let data = image.pngData() {
                    try data.write(to: fileURL)
                    DispatchQueue.main.async {
                        completion(fileURL)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } catch {
                print("Error saving image to temporary file: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
}
