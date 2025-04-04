//
//  FocusEntity.swift
//  Surface Capture
//
//  Created by Ashley Davison on 04/04/2025.
//

/*
import RealityKit
import ARKit
import Combine
import SwiftUI

/// A focus entity that can be moved around in AR space to guide model placement
class FocusEntity {
    // MARK: - Properties
    
    /// The main entity visible in the scene
    private var focusEntity: ModelEntity?
    
    /// The anchor where the focus entity is placed
    private var anchor: AnchorEntity?
    
    /// The ARView where this entity is displayed
    private weak var arView: ARView?
    
    /// Whether the focus entity is currently active/visible
    private(set) var isActive = false
    
    /// Cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// The current position of the focus entity in world space
    private(set) var currentWorldPosition: SIMD3<Float>?
    
    /// The normal of the surface at the current position
    private(set) var currentSurfaceNormal: SIMD3<Float>?
    
    // MARK: - Initialization
    
    /// Creates a focus entity for the given ARView
    /// - Parameter arView: The ARView to attach the focus entity to
    init(for arView: ARView) {
        self.arView = arView
        
        setupFocusEntity()
    }
    
    // MARK: - Setup
    
    /// Creates the visual components of the focus entity
    private func setupFocusEntity() {
        // Create a circular plane as the focus indicator
        let mesh = MeshResource.generatePlane(width: 0.05, height: 0.05)
        
        // Create a semi-transparent material with a circular cutout
        var material = UnlitMaterial()
        material.color = .init(tint: .white.withAlphaComponent(0.8), texture: nil)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        
        // Create the focus entity
        focusEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Add a ring around the edge for visibility
        addRingToFocusEntity()
    }
    
    /// Adds a ring around the edge of the focus entity for better visibility
    private func addRingToFocusEntity() {
        guard let focusEntity = focusEntity else { return }
        
        // Create a thin torus for the ring
        let ringMesh = MeshResource.generateCylinder(height: 0.001, radius: 0.025)
        var ringMaterial = UnlitMaterial()
        ringMaterial.color = .init(tint: .systemBlue.withAlphaComponent(0.8), texture: nil)
        
        let ringEntity = ModelEntity(mesh: ringMesh, materials: [ringMaterial])
        
        // Add the ring to the focus entity
        focusEntity.addChild(ringEntity)
        
        // Add a slight animation to make it more visible
        let pulseAnimation = Animation.easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        
        ringEntity.setScale([1.0, 1.0, 1.0], relativeTo: focusEntity)
    }
    
    // MARK: - Public API
    
    /// Activates the focus entity at the given screen point
    /// - Parameters:
    ///   - screenPoint: The point on the screen where the focus entity should appear
    ///   - completion: Called when the focus entity is successfully placed
    /// - Returns: True if the focus entity was successfully placed, false otherwise
    @discardableResult
    func activate(at screenPoint: CGPoint, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let arView = arView else {
            completion?(false)
            return false
        }
        
        // Perform a raycast to find a surface
        guard let raycastResult = performRaycast(from: screenPoint, in: arView) else {
            completion?(false)
            return false
        }
        
        // Create an anchor at the raycast hit location
        placeAnchor(at: raycastResult.worldTransform)
        
        // Store the current position and normal
        currentWorldPosition = SIMD3<Float>(
            raycastResult.worldTransform.columns.3.x,
            raycastResult.worldTransform.columns.3.y,
            raycastResult.worldTransform.columns.3.z
        )
        
        currentSurfaceNormal = SIMD3<Float>(
            raycastResult.worldTransform.columns.1.x,
            raycastResult.worldTransform.columns.1.y,
            raycastResult.worldTransform.columns.1.z
        )
        
        isActive = true
        completion?(true)
        return true
    }
    
    /// Updates the position of the focus entity based on a new screen point
    /// - Parameter screenPoint: The new screen point to move the focus entity to
    /// - Returns: True if the focus entity was successfully updated, false otherwise
    @discardableResult
    func update(to screenPoint: CGPoint) -> Bool {
        guard let arView = arView, isActive else { return false }
        
        // Perform a raycast at the new screen point
        guard let raycastResult = performRaycast(from: screenPoint, in: arView) else { return false }
        
        // Update the anchor's position
        anchor?.transform.matrix = raycastResult.worldTransform
        
        // Update stored position and normal
        currentWorldPosition = SIMD3<Float>(
            raycastResult.worldTransform.columns.3.x,
            raycastResult.worldTransform.columns.3.y,
            raycastResult.worldTransform.columns.3.z
        )
        
        currentSurfaceNormal = SIMD3<Float>(
            raycastResult.worldTransform.columns.1.x,
            raycastResult.worldTransform.columns.1.y,
            raycastResult.worldTransform.columns.1.z
        )
        
        return true
    }
    
    /// Deactivates and removes the focus entity from the scene
    func deactivate() {
        if let anchor = anchor {
            arView?.scene.anchors.remove(anchor)
        }
        
        anchor = nil
        isActive = false
        currentWorldPosition = nil
        currentSurfaceNormal = nil
    }
    
    // MARK: - Helper Methods
    
    /// Performs a raycast from the given screen point
    /// - Parameters:
    ///   - screenPoint: The point on the screen to raycast from
    ///   - arView: The ARView to perform the raycast in
    /// - Returns: The raycast result if successful, nil otherwise
    private func performRaycast(from screenPoint: CGPoint, in arView: ARView) -> ARRaycastResult? {
        // Try to hit an existing plane
        let results = arView.raycast(from: screenPoint,
                                    allowing: .estimatedPlane,
                                    alignment: .any)
        
        if let planeHit = results.first {
            return planeHit
        }
        
        // If no plane hit, try to hit any feature point
        let featureResults = arView.raycast(from: screenPoint,
                                          allowing: .existingPlaneInfinite,
                                          alignment: .any)
        
        return featureResults.first
    }
    
    /// Places the focus entity at the given world transform
    /// - Parameter worldTransform: The transform where the focus entity should be placed
    private func placeAnchor(at worldTransform: simd_float4x4) {
        // Remove previous anchor if it exists
        if let anchor = anchor {
            arView?.scene.anchors.remove(anchor)
        }
        
        // Create a new anchor
        let newAnchor = AnchorEntity(world: worldTransform)
        
        // Add the focus entity to the anchor
        if let focusEntity = focusEntity {
            newAnchor.addChild(focusEntity)
            
            // Make sure the entity is oriented correctly
            focusEntity.orientation = simd_quatf(matrix_float3x3(
                worldTransform.columns.0.xyz,
                worldTransform.columns.1.xyz,
                worldTransform.columns.2.xyz
            ))
        }
        
        // Add the anchor to the scene
        arView?.scene.addAnchor(newAnchor)
        
        // Store the anchor
        self.anchor = newAnchor
    }
}

// MARK: - Helper Extensions

extension SIMD4 {
    var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(x: self.x, y: self.y, z: self.z)
    }
}
*/
