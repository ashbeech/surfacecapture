//
//  CustomMeshVisualizer.swift
//  Surface Capture App
//

/*
import SwiftUI
import RealityKit
import ARKit
import Combine

/// A hybrid solution that directly finds ARViews and applies custom mesh visualization
public class CustomMeshVisualizer {
    // Session reference
    private weak var session: ObjectCaptureSession?
    
    // Visualization settings
    private var isWireframe: Bool = true
    private var isRainbowMode: Bool = true
    private var currentOpacity: Float = 0.7
    private var currentColor: UIColor = .white
    
    // Track found ARViews and their visualizers
    private var foundARViews: [ARView: SceneMeshVisualizer] = [:]
    private var searchTimer: Timer?
    private var isEnabled: Bool = true
    
    public init(session: ObjectCaptureSession) {
        self.session = session
        startSearchingForARViews()
    }
    
    // MARK: - Finding ARViews
    
    private func startSearchingForARViews() {
        // Initial search
        findAllARViews()
        
        // Set up timer to keep checking for ARViews
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            self?.findAllARViews()
            
            // Stop after a reasonable time if we've found at least one ARView
            if let self = self, !self.foundARViews.isEmpty && timer.fireDate.timeIntervalSinceNow > 5.0 {
                timer.invalidate()
                self.searchTimer = nil
            }
        }
    }
    
    private func findAllARViews() {
        for window in UIApplication.shared.windows {
            findARViews(in: window)
        }
    }
    
    private func findARViews(in view: UIView) {
        // Check if this view is an ARView that we haven't found yet
        if let arView = view as? ARView, foundARViews[arView] == nil {
            // Create a new visualizer for this ARView
            let visualizer = SceneMeshVisualizer(arView: arView)
            
            // Apply current settings
            if isEnabled {
                visualizer.enable()
                applyCurrentSettings(to: visualizer)
            }
            
            // Store the reference
            foundARViews[arView] = visualizer
        }
        
        // Check all subviews recursively
        for subview in view.subviews {
            findARViews(in: subview)
        }
    }
    
    // MARK: - Public API
    
    public func enable() {
        isEnabled = true
        
        // Enable all existing visualizers
        for visualizer in foundARViews.values {
            visualizer.enable()
            applyCurrentSettings(to: visualizer)
        }
        
        // If we don't have any visualizers yet, restart search
        if foundARViews.isEmpty {
            startSearchingForARViews()
        }
    }
    
    public func disable() {
        isEnabled = false
        
        // Disable all existing visualizers
        for visualizer in foundARViews.values {
            visualizer.disable()
        }
        
        // Stop searching if we're still searching
        searchTimer?.invalidate()
        searchTimer = nil
    }
    
    public func setWireframeMode(_ enabled: Bool) {
        isWireframe = enabled
        
        // Apply to all existing visualizers
        for visualizer in foundARViews.values {
            visualizer.setWireframeMode(enabled)
        }
    }
    
    public func setRainbowMode(_ enabled: Bool) {
        isRainbowMode = enabled
        
        // Apply to all existing visualizers
        for visualizer in foundARViews.values {
            visualizer.setRainbowMode(enabled)
        }
    }
    
    public func setMeshOpacity(_ opacity: Float) {
        currentOpacity = opacity
        
        // Apply to all existing visualizers
        for visualizer in foundARViews.values {
            visualizer.setMeshOpacity(opacity)
        }
    }
    
    public func setMeshColor(_ color: UIColor) {
        currentColor = color
        
        // Apply to all existing visualizers
        for visualizer in foundARViews.values {
            visualizer.setMeshColor(color)
        }
    }
    
    private func applyCurrentSettings(to visualizer: SceneMeshVisualizer) {
        visualizer.setWireframeMode(isWireframe)
        visualizer.setRainbowMode(isRainbowMode)
        visualizer.setMeshOpacity(currentOpacity)
        
        if !isRainbowMode {
            visualizer.setMeshColor(currentColor)
        }
    }
    
    public func cleanup() {
        // Clean up all visualizers
        for visualizer in foundARViews.values {
            visualizer.cleanup()
        }
        
        foundARViews.removeAll()
        
        // Stop searching
        searchTimer?.invalidate()
        searchTimer = nil
    }
}
// MARK: - SwiftUI View Modifier

struct CustomMeshVisualizerModifier: ViewModifier {
    @State private var visualizer: CustomMeshVisualizer?
    private let session: ObjectCaptureSession
    @Binding private var isEnabled: Bool
    @Binding private var wireframeMode: Bool
    @Binding private var rainbowMode: Bool
    @Binding private var opacity: Float
    private var color: UIColor
    
    init(
        session: ObjectCaptureSession,
        isEnabled: Binding<Bool>,
        wireframeMode: Binding<Bool>,
        rainbowMode: Binding<Bool>,
        opacity: Binding<Float>,
        color: UIColor = .white
    ) {
        self.session = session
        self._isEnabled = isEnabled
        self._wireframeMode = wireframeMode
        self._rainbowMode = rainbowMode
        self._opacity = opacity
        self.color = color
    }
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Create the visualizer when the view appears
                let visualizer = CustomMeshVisualizer(session: session)
                self.visualizer = visualizer
                
                // Apply initial settings
                updateVisualizerSettings()
            }
            .onChange(of: isEnabled) { _ in updateVisualizerSettings() }
            .onChange(of: wireframeMode) { _ in updateVisualizerSettings() }
            .onChange(of: rainbowMode) { _ in updateVisualizerSettings() }
            .onChange(of: opacity) { _ in updateVisualizerSettings() }
            .onDisappear {
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

// MARK: - Extension for SwiftUI View

public extension View {
    /// Add custom scene mesh visualization to an ObjectCaptureView with all customization options
    /// - Parameters:
    ///   - session: The ObjectCaptureSession
    ///   - isEnabled: Whether the visualization is enabled
    ///   - wireframeMode: Whether to show wireframe rendering
    ///   - rainbowMode: Whether to use rainbow coloring by height
    ///   - opacity: Opacity of the visualization
    ///   - color: Color to use when not in rainbow mode
    /// - Returns: Modified view with scene mesh visualization
    func customSceneMeshVisualization(
        session: ObjectCaptureSession,
        isEnabled: Binding<Bool> = .constant(true),
        wireframeMode: Binding<Bool> = .constant(false),
        rainbowMode: Binding<Bool> = .constant(true),
        opacity: Binding<Float> = .constant(0.7),
        color: UIColor = .white
    ) -> some View {
        self.modifier(CustomMeshVisualizerModifier(
            session: session,
            isEnabled: isEnabled,
            wireframeMode: wireframeMode,
            rainbowMode: rainbowMode,
            opacity: opacity,
            color: color
        ))
    }
}
*/
