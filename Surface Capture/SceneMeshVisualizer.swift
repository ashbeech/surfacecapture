//
//  SceneMeshVisualizer.swift
//  Surface Capture
//
//  Created by Ashley Davison on 04/04/2025.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

/// A utility class that provides customizable visualization of AR scene understanding meshes
public class SceneMeshVisualizer {
    // The ARView to visualize
    private weak var arView: ARView?
    
    // Cancellables
    private var sceneObserver: Cancellable?
    private var updateTimer: Timer?
    
    // Visualization settings
    private var currentColor: UIColor = .white
    private var currentOpacity: Float = 0.7
    private var isWireframe: Bool = false
    private var isRainbowMode: Bool = true
    public var isEnabled: Bool = true
    
    // Store reference to scene understanding entities for tracking
    private var meshEntities: [Entity] = []
    
    /// Initialize with an ARView instance
    /// - Parameter arView: The ARView to visualize
    public init(arView: ARView) {
        self.arView = arView
        setupSceneUnderstanding()
    }
    
    /// Enables the scene mesh visualization
    public func enable() {
        guard let arView = arView else { return }
        
        isEnabled = true
        
        // Configure AR session for scene reconstruction if not already done
        configureARSession()
        
        // Enable scene understanding features
        enableSceneUnderstanding()
        
        // Set up scene observer for visualization updates
        setupSceneObserver()
        
        // Start periodic updates
        startUpdateTimer()
        
        // Force an immediate update
        updateMeshVisualization()
    }
    
    /// Disables the scene mesh visualization
    public func disable() {
        isEnabled = false
        
        // Stop update timer
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Cancel scene observer
        sceneObserver?.cancel()
        sceneObserver = nil
        
        // Hide all mesh entities
        for entity in meshEntities {
            entity.isEnabled = false
        }
    }
    
    /// Sets the mesh color when not in rainbow mode
    /// - Parameter color: The color to apply to the mesh
    public func setMeshColor(_ color: UIColor) {
        currentColor = color
        isRainbowMode = false
        updateMeshVisualization()
    }
    
    /// Sets the mesh opacity/transparency
    /// - Parameter opacity: Opacity value (0.0-1.0)
    public func setMeshOpacity(_ opacity: Float) {
        currentOpacity = max(0.0, min(1.0, opacity))
        updateMeshVisualization()
    }
    
    /// Toggles wireframe rendering mode
    /// - Parameter enabled: Whether wireframe mode is enabled
    public func setWireframeMode(_ enabled: Bool) {
        isWireframe = enabled
        updateMeshVisualization()
    }
    
    /// Toggles rainbow coloring (similar to debug visualization)
    /// - Parameter enabled: Whether rainbow mode is enabled
    public func setRainbowMode(_ enabled: Bool) {
        isRainbowMode = enabled
        updateMeshVisualization()
    }
    
    /// Cleans up resources when no longer needed
    public func cleanup() {
        disable()
        updateTimer?.invalidate()
        updateTimer = nil
        sceneObserver?.cancel()
        sceneObserver = nil
        
        // Remove all materials to restore default appearance
        resetMeshMaterials()
    }
    
    // MARK: - Private Methods
    
    private func setupSceneUnderstanding() {
        // Initial setup
        configureARSession()
        enableSceneUnderstanding()
    }
    
    private func configureARSession() {
        guard let arView = arView else { return }
        
        // Only configure if needed
        if let configuration = arView.session.configuration as? ARWorldTrackingConfiguration {
            // Check if we need to update the configuration
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                // Only update if scene reconstruction isn't already enabled
                if configuration.sceneReconstruction != .mesh {
                    let updatedConfig = configuration.copy() as! ARWorldTrackingConfiguration
                    updatedConfig.sceneReconstruction = .mesh
                    
                    // Enable scene depth for better mesh quality if supported
                    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                        updatedConfig.frameSemantics.insert(.sceneDepth)
                    }
                    
                    // Update configuration with existing session state to avoid resetting tracking
                    arView.session.run(updatedConfig)
                }
            } else {
                print("Scene reconstruction not supported on this device")
            }
        } else {
            // No existing configuration, create a new one
            let configuration = ARWorldTrackingConfiguration()
            
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                configuration.sceneReconstruction = .mesh
                
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    configuration.frameSemantics.insert(.sceneDepth)
                }
            }
            
            arView.session.run(configuration)
        }
    }
    
    private func enableSceneUnderstanding() {
        guard let arView = arView else { return }
        
        // Enable scene understanding features in RealityKit
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        arView.environment.sceneUnderstanding.options.insert(.physics)
        arView.environment.sceneUnderstanding.options.insert(.collision)
        arView.environment.sceneUnderstanding.options.insert(.receivesLighting)
    }
    
    private func setupSceneObserver() {
        sceneObserver?.cancel()
        
        // Subscribe to scene updates to track new mesh entities
        guard let arView = arView else { return }
        
        sceneObserver = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            // Track entities but don't update visualization on every frame
            // (Visualization will be updated by the timer for better performance)
            self?.trackMeshEntities()
        }
    }
    
    private func startUpdateTimer() {
        // Create a timer that updates the visualization at a reasonable interval
        updateTimer?.invalidate()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateMeshVisualization()
        }
    }
    
    private func trackMeshEntities() {
        guard let arView = arView, isEnabled else { return }
        
        // Query for scene understanding entities
        let sceneUnderstandingQuery = EntityQuery(where: .has(SceneUnderstandingComponent.self) && .has(ModelComponent.self))
        let queryResults = arView.scene.performQuery(sceneUnderstandingQuery)
        
        // Store reference to mesh entities
        meshEntities = Array(queryResults)
    }
    
    private func updateMeshVisualization() {
        guard isEnabled else { return }
        
        // Update materials on all tracked mesh entities
        for entity in meshEntities {
            if let modelComponent = entity.components[ModelComponent.self] as? ModelComponent {
                // Apply current visualization settings to the model
                if isWireframe {
                    createWireframeMaterial(for: entity)
                } else if isRainbowMode {
                    createRainbowMaterial(for: entity)
                } else {
                    createSolidMaterial(for: entity)
                }
            }
        }
    }
    
    private func resetMeshMaterials() {
        // Reset mesh entities to their original state
        for entity in meshEntities {
            if var modelComponent = entity.components[ModelComponent.self] as? ModelComponent {
                // Create a standard physically based material
                var material = PhysicallyBasedMaterial()
                material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white)
                material.roughness = 0.5
                material.metallic = 0.0
                modelComponent.materials = [material]
                entity.components[ModelComponent.self] = modelComponent
            }
        }
    }
    
    private func createWireframeMaterial(for entity: Entity) {
        if var modelComponent = entity.components[ModelComponent.self] as? ModelComponent {
            var material = UnlitMaterial()
            material.color = PhysicallyBasedMaterial.BaseColor(tint: currentColor.withAlphaComponent(CGFloat(currentOpacity)))
            material.triangleFillMode = .lines
            modelComponent.materials = [material]
            entity.components[ModelComponent.self] = modelComponent
        }
    }
    
    private func createSolidMaterial(for entity: Entity) {
        if var modelComponent = entity.components[ModelComponent.self] as? ModelComponent {
            var material = PhysicallyBasedMaterial()
            material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: currentColor.withAlphaComponent(CGFloat(currentOpacity)))
            material.roughness = 0.5
            material.metallic = 0.0
            // Set to semi-transparent
            material.blending = .transparent(opacity: .init(floatLiteral: Float(Double(currentOpacity))))
            modelComponent.materials = [material]
            entity.components[ModelComponent.self] = modelComponent
        }
    }
    
    private func createRainbowMaterial(for entity: Entity) {
        // For rainbow mode, use a simple colored material based on entity position
        if var modelComponent = entity.components[ModelComponent.self] as? ModelComponent {
            // Get entity's position in world space
            let position = entity.position(relativeTo: nil)
            
            // Create a hue value based on height (y-axis)
            // Normalize height to 0-1 range (assuming reasonable room dimensions)
            let minHeight: Float = -1.0
            let maxHeight: Float = 3.0
            let normalizedHeight = (position.y - minHeight) / (maxHeight - minHeight)
            let clampedHeight = max(0, min(1, normalizedHeight))
            
            // Create a color using HSB where height determines hue
            let color = UIColor(hue: CGFloat(clampedHeight),
                               saturation: 1.0,
                               brightness: 1.0,
                               alpha: CGFloat(currentOpacity))
            
            if isWireframe {
                var material = UnlitMaterial()
                material.color = PhysicallyBasedMaterial.BaseColor(tint: color)
                material.triangleFillMode = .lines
                modelComponent.materials = [material]
            } else {
                var material = PhysicallyBasedMaterial()
                material.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
                material.roughness = 0.5
                material.metallic = 0.0
                material.blending = .transparent(opacity: .init(floatLiteral: Float(Double(currentOpacity))))
                modelComponent.materials = [material]
            }
            
            entity.components[ModelComponent.self] = modelComponent
        }
    }
}

// MARK: - SwiftUI Wrapper for the Visualizer
public struct SceneMeshVisualizerView: ViewModifier {
    // Visualization options
    @Binding private var isEnabled: Bool
    @Binding private var wireframeMode: Bool
    @Binding private var rainbowMode: Bool
    @Binding private var opacity: Float
    private var color: UIColor
    
    // EnvironmentObject to access ARView
    @EnvironmentObject private var arViewContainer: ARViewContainer
    
    // Private state for the visualizer
    @State private var visualizer: SceneMeshVisualizer?
    
    /// Initialize the visualizer view modifier
    /// - Parameters:
    ///   - isEnabled: Binding to control visibility
    ///   - wireframeMode: Binding to toggle wireframe rendering
    ///   - rainbowMode: Binding to toggle rainbow coloring
    ///   - opacity: Binding to control opacity
    ///   - color: Color to use when not in rainbow mode
    public init(
        isEnabled: Binding<Bool>,
        wireframeMode: Binding<Bool>,
        rainbowMode: Binding<Bool>,
        opacity: Binding<Float>,
        color: UIColor = .white
    ) {
        self._isEnabled = isEnabled
        self._wireframeMode = wireframeMode
        self._rainbowMode = rainbowMode
        self._opacity = opacity
        self.color = color
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                // Create visualizer when view appears
                if let arView = arViewContainer.arView {
                    let sceneMeshViz = SceneMeshVisualizer(arView: arView)
                    self.visualizer = sceneMeshViz
                    
                    // Apply initial settings
                    updateVisualizerSettings()
                }
            }
            .onChange(of: isEnabled) { _ in updateVisualizerSettings() }
            .onChange(of: wireframeMode) { _ in updateVisualizerSettings() }
            .onChange(of: rainbowMode) { _ in updateVisualizerSettings() }
            .onChange(of: opacity) { _ in updateVisualizerSettings() }
            .onDisappear {
                // Clean up when view disappears
                visualizer?.cleanup()
                visualizer = nil
            }
    }
    
    private func updateVisualizerSettings() {
        guard let visualizer = visualizer else { return }
        
        if isEnabled {
            visualizer.enable()
            visualizer.setWireframeMode(wireframeMode)
            visualizer.setRainbowMode(rainbowMode)
            visualizer.setMeshOpacity(opacity)
            
            if !rainbowMode {
                visualizer.setMeshColor(color)
            }
        } else {
            visualizer.disable()
        }
    }
}

// MARK: - Environment Object for ARView Access
public class ARViewContainer: ObservableObject {
    public var arView: ARView?
    
    public init(arView: ARView? = nil) {
        self.arView = arView
    }
}

// MARK: - Extension for SwiftUI View
public extension View {
    /// Add scene mesh visualization to an AR view
    /// - Parameters:
    ///   - isEnabled: Whether visualization is enabled
    ///   - wireframeMode: Whether to show wireframe rendering
    ///   - rainbowMode: Whether to use rainbow coloring by height
    ///   - opacity: Opacity of the visualization
    ///   - color: Color to use when not in rainbow mode
    /// - Returns: Modified view with scene mesh visualization
    func sceneMeshVisualization(
        isEnabled: Binding<Bool>,
        wireframeMode: Binding<Bool> = .constant(false),
        rainbowMode: Binding<Bool> = .constant(true),
        opacity: Binding<Float> = .constant(0.7),
        color: UIColor = .white
    ) -> some View {
        self.modifier(SceneMeshVisualizerView(
            isEnabled: isEnabled,
            wireframeMode: wireframeMode,
            rainbowMode: rainbowMode,
            opacity: opacity,
            color: color
        ))
    }
}
