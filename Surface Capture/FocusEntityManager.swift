//
//  FocusEntityManager.swift
//  Surface Capture
//
//  Created by Ashley Davison on 04/04/2025.
//

/*
import RealityKit
import ARKit
import Combine
import UIKit

/// Manager class that handles the focus entity and related gestures
class FocusEntityManager: NSObject {
    // MARK: - Properties
    
    /// The focus entity being managed
    private let focusEntity: FocusEntity
    
    /// The AR view that this manager is operating on
    private weak var arView: ARView?
    
    /// Callback for when placement occurs
    var onPlacement: ((SIMD3<Float>, SIMD3<Float>) -> Void)?
    
    /// The long press gesture recognizer
    private var longPressGesture: UILongPressGestureRecognizer?
    
    /// The pan gesture recognizer activated after long press
    private var panGesture: UIPanGestureRecognizer?
    
    /// Flag indicating if we are currently in a placement gesture
    private var isInPlacementGesture = false
    
    /// The lock constraints applied during placement
    var lockConstraints: PlacementConstraints = .none
    
    // MARK: - Initialization
    
    /// Creates a new focus entity manager for the given AR view
    /// - Parameter arView: The AR view to manage focus entity for
    init(for arView: ARView) {
        self.arView = arView
        self.focusEntity = FocusEntity(for: arView)
        
        super.init()
        
        setupGestures()
    }
    
    // MARK: - Setup
    
    /// Sets up the gesture recognizers
    private func setupGestures() {
        guard let arView = arView else { return }
        
        // Create long press gesture
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        arView.addGestureRecognizer(longPress)
        self.longPressGesture = longPress
        
        // Create pan gesture (initially disabled)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.isEnabled = false
        arView.addGestureRecognizer(pan)
        self.panGesture = pan
    }
    
    // MARK: - Gesture Handling
    
    /// Handles the long press gesture
    /// - Parameter gesture: The long press gesture recognizer
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let arView = arView else { return }
        
        switch gesture.state {
        case .began:
            // Start the placement gesture
            isInPlacementGesture = true
            
            // Activate the focus entity at the touch location
            let touchLocation = gesture.location(in: arView)
            let success = focusEntity.activate(at: touchLocation)
            
            if success {
                // Enable pan gesture for tracking
                panGesture?.isEnabled = true
                
                // Give haptic feedback
                let feedback = UIImpactFeedbackGenerator(style: .medium)
                feedback.impactOccurred()
            } else {
                // If we couldn't place the focus entity, cancel the gesture
                isInPlacementGesture = false
            }
            
        case .ended, .cancelled:
            if isInPlacementGesture {
                // Finalize placement
                if let position = focusEntity.currentWorldPosition,
                   let normal = focusEntity.currentSurfaceNormal {
                    // Call the placement callback
                    onPlacement?(position, normal)
                    
                    // Give haptic feedback
                    let feedback = UIImpactFeedbackGenerator(style: .medium)
                    feedback.impactOccurred()
                }
                
                // Clean up
                focusEntity.deactivate()
                isInPlacementGesture = false
                panGesture?.isEnabled = false
            }
            
        default:
            break
        }
    }
    
    /// Handles the pan gesture
    /// - Parameter gesture: The pan gesture recognizer
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let arView = arView, isInPlacementGesture else { return }
        
        switch gesture.state {
        case .changed:
            // Update the focus entity position
            let touchLocation = gesture.location(in: arView)
            
            // Apply any locked constraints if needed
            let constrainedLocation = applyConstraints(to: touchLocation)
            
            let success = focusEntity.update(to: constrainedLocation)
            
            if !success {
                // If we lost tracking during panning, try to look around that area
                let searchRadius: CGFloat = 20
                for xOffset in stride(from: -searchRadius, through: searchRadius, by: 10) {
                    for yOffset in stride(from: -searchRadius, through: searchRadius, by: 10) {
                        let searchPoint = CGPoint(
                            x: constrainedLocation.x + xOffset,
                            y: constrainedLocation.y + yOffset
                        )
                        if focusEntity.update(to: searchPoint) {
                            break
                        }
                    }
                }
            }
            
        case .ended, .cancelled:
            // End the gesture if the pan ends/cancels before the long press
            if longPressGesture?.state != .changed && longPressGesture?.state != .began {
                if let position = focusEntity.currentWorldPosition,
                   let normal = focusEntity.currentSurfaceNormal {
                    onPlacement?(position, normal)
                }
                
                focusEntity.deactivate()
                isInPlacementGesture = false
                panGesture?.isEnabled = false
            }
            
        default:
            break
        }
    }
    
    /// Applies the current constraints to the touch location
    /// - Parameter location: The original touch location
    /// - Returns: The constrained touch location
    private func applyConstraints(to location: CGPoint) -> CGPoint {
        var result = location
        
        if case .verticalPlaneOnly = lockConstraints {
            // For vertical plane only, we would need to modify the raycast query
            // but this is handled internally by the focus entity
        } else if case .horizontalPlaneOnly = lockConstraints {
            // For horizontal plane only, we would need to modify the raycast query
            // but this is handled internally by the focus entity
        }
        
        return result
    }
    
    // MARK: - Public API
    
    /// Updates the constraints for placement
    /// - Parameter constraints: The new constraints to apply
    func updateConstraints(_ constraints: PlacementConstraints) {
        self.lockConstraints = constraints
    }
    
    /// Cleans up resources
    func cleanup() {
        // Deactivate the focus entity
        focusEntity.deactivate()
        
        // Remove gesture recognizers
        if let longPressGesture = longPressGesture, let arView = arView {
            arView.removeGestureRecognizer(longPressGesture)
        }
        
        if let panGesture = panGesture, let arView = arView {
            arView.removeGestureRecognizer(panGesture)
        }
    }
}

// MARK: - Gesture Delegate

extension FocusEntityManager: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only allow simultaneous recognition between our long press and pan gestures
        return (gestureRecognizer == longPressGesture && otherGestureRecognizer == panGesture) ||
               (gestureRecognizer == panGesture && otherGestureRecognizer == longPressGesture)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't process touches that started on UI controls
        if let view = touch.view, view is UIControl {
            return false
        }
        return true
    }
}

// MARK: - Supporting Types

/// Constraints that can be applied to the placement
enum PlacementConstraints {
    /// No constraints
    case none
    
    /// Only allow placement on horizontal planes
    case horizontalPlaneOnly
    
    /// Only allow placement on vertical planes
    case verticalPlaneOnly
}
*/
