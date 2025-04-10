//
//  FocusEntityManager.swift
//  Surface Capture
//
//  Created by Ashley Davison on 09/04/2025.
//

import RealityKit
import Combine
import ARKit

/// Manager class to handle FocusEntity creation, updates and lifecycle
import RealityKit
import Combine
import ARKit

/// Manager class to handle FocusEntity creation, updates and lifecycle
class FocusEntityManager {
    // The focus entity instance
    private var focusEntity: FocusEntity?
    
    private var initialMaterials: [Material]?
    
    // The ARView where the focus entity will be displayed
    private weak var arView: ARView?
    
    // Constraints for the focus entity
    private var constraints: FocusEntityConstraints = .none
    
    // Store cancelables to avoid memory leaks
    private var cancellables = Set<AnyCancellable>()

    // Callback for when placement occurs
    var onPlacement: ((_ position: SIMD3<Float>, _ normal: SIMD3<Float>) -> Void)?
    
    // Track the last position for tap to place functionality
    private var lastPosition: SIMD3<Float>?
    private var lastNormal: SIMD3<Float>?
    
    // Enum to define different constraints for the focus entity
    enum FocusEntityConstraints {
        case none
        case horizontalPlaneOnly
        case verticalPlaneOnly
    }
    
    /// Initialize the manager with an ARView
    /// - Parameter arView: The ARView where the focus entity will be shown
    init(for arView: ARView) {
        self.arView = arView
        setupFocusEntity()
    }
    
    /// Setup the focus entity with the ARView
    private func setupFocusEntity() {
        guard let arView = arView else { return }
        
        // Create the focus entity with default style
        _ = FocusEntity(on: arView, style: .classic(color: .green))
        //focusEntity.delegate = self
        //self.focusEntity = focusEntity
        
        print("set-up")
        
        // Set auto update to true
        //focusEntity.setAutoUpdate(to: true)
    }
    
    /*
    /// Update the constraints for the focus entity
    /// - Parameter constraints: The new constraints to apply
    func updateConstraints(_ constraints: FocusEntityConstraints) {
        self.constraints = constraints
        
        // Update raycast targets based on constraints
        if let focusEntity = focusEntity {
            switch constraints {
            case .none:
                focusEntity.allowedRaycasts = [.existingPlaneGeometry, .estimatedPlane]
            case .horizontalPlaneOnly:
                focusEntity.allowedRaycasts = [.existingPlaneGeometry]
            case .verticalPlaneOnly:
                focusEntity.allowedRaycasts = [.existingPlaneGeometry]
            }
        }
    }
     */
    
    /// Toggle the visibility of the focus entity
    /// - Parameter isVisible: Whether the focus entity should be visible
    func setVisible(_ isVisible: Bool) {
        focusEntity?.isEnabled = isVisible
    }
    
    /// Process tap on the ARView for placement
    /// - Parameter location: The screen location of the tap
    /*
    func processTap(at location: CGPoint) {
        guard let position = lastPosition,
              let normal = lastNormal else { return }
        
        // Call the placement callback
        onPlacement?(position, normal)
    }
     */
    
    /// Cleanup resources
    func cleanup() {
        // Cancel all subscriptions
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        
        // Destroy the focus entity
        focusEntity?.destroy()
        focusEntity = nil
    }
}

// MARK: - FocusEntityDelegate Implementation
extension FocusEntityManager: FocusEntityDelegate {
    func focusEntity(_ focusEntity: FocusEntity, trackingUpdated trackingState: FocusEntity.State, oldState: FocusEntity.State?) {
        // Filter raycast results based on constraints
        switch trackingState {
        case .tracking(let raycastResult, _):
            /*
            // Extract the position from the world transform matrix
            let worldTransform = raycastResult.worldTransform
            // Extract the translation component from the transform matrix
            lastPosition = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            
            // Extract normal from the transform
            let normalTransform = raycastResult.worldTransform
            lastNormal = SIMD3<Float>(normalTransform.columns.1.x, normalTransform.columns.1.y, normalTransform.columns.1.z)

            // Apply constraints if needed
            if case .horizontalPlaneOnly = constraints {
                guard let planeAnchor = raycastResult.anchor as? ARPlaneAnchor,
                      planeAnchor.alignment == .horizontal else {
                    focusEntity.isEnabled = false
                    return
                }
                focusEntity.isEnabled = true
            } else if case .verticalPlaneOnly = constraints {
                guard let planeAnchor = raycastResult.anchor as? ARPlaneAnchor,
                      planeAnchor.alignment == .vertical else {
                    focusEntity.isEnabled = false
                    return
                }
                focusEntity.isEnabled = true
            } else {
                focusEntity.isEnabled = true
            }
             */
            focusEntity.isEnabled = true

        case .initializing:
            lastPosition = nil
            lastNormal = nil
        }
    }
    
    func focusEntity(_ focusEntity: FocusEntity, planeChanged: ARPlaneAnchor?, oldPlane: ARPlaneAnchor?) {
        // Handle plane changes if needed
    }
}
