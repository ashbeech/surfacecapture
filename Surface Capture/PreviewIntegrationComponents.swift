import SwiftUI
import RealityKit
import MetalKit
import Combine

// MARK: - Preview Container View
struct MeshPreviewContainer: UIViewRepresentable {
    let previewSystem: RealtimeMeshPreviewSystem
    
    func makeUIView(context: Context) -> MTKView {
        let view = previewSystem.previewView
        view.layer.cornerRadius = 15
        view.layer.masksToBounds = true
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        // Updates handled by preview system
    }
}

// MARK: - Enhanced Object Capture View
struct EnhancedObjectCaptureView: View {
    @EnvironmentObject var appModel: AppDataModel
    let session: ObjectCaptureSession
    
    // State management
    @StateObject private var previewSystemManager = PreviewSystemManager()
    @State private var showPreview = true
    @State private var showGuide = true
    @State private var isCapturing = false
    
    var body: some View {
        ZStack {
            // Main AR View with ObjectCaptureSession
            ObjectCaptureView(session: session)
                .overlay(alignment: .top) {
                    if isCapturing {
                        CaptureQualityOverlay(
                            metrics: appModel.captureQualityMetrics,
                            qualityStatus: appModel.captureQualityStatus
                        )
                        .padding(.top, 50)
                    }
                }
                .overlay(alignment: .bottom) {
                    controlsOverlay
                }
                .overlay(alignment: .bottomTrailing) {
                    if showPreview, let system = previewSystemManager.previewSystem {
                        previewOverlay(system: system)
                    }
                }
                .overlay(alignment: .center) {
                    if showGuide {
                        GuideOverlay(isVisible: $showGuide)
                    }
                }
        }
        .onAppear {
            setupSession()
        }
        .onDisappear {
            cleanupSession()
        }
    }
    
    private func previewOverlay(system: RealtimeMeshPreviewSystem) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Preview window
            MeshPreviewContainer(previewSystem: system)
                .frame(width: 180, height: 180)
                .cornerRadius(15)
                .shadow(radius: 5)
            
            // Quality indicators
            HStack(spacing: 12) {
                QualityIndicator(
                    icon: "camera.metering.matrix",
                    value: system.depthQuality,
                    label: "Depth"
                )
                
                QualityIndicator(
                    icon: "chart.bar.fill",
                    value: system.averageConfidence,
                    label: "Quality"
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(8)
        }
        .padding()
    }
    
    private var controlsOverlay: some View {
        VStack(spacing: 20) {
            if isCapturing {
                HStack(spacing: 20) {
                    // Preview toggle
                    Button(action: {
                        withAnimation {
                            showPreview.toggle()
                        }
                    }) {
                        Image(systemName: showPreview ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    
                    // Guide toggle
                    Button(action: {
                        withAnimation {
                            showGuide.toggle()
                        }
                    }) {
                        Image(systemName: showGuide ? "questionmark.circle.fill" : "questionmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Finish button
                    Button(action: {
                        withAnimation {
                            endCapture()
                        }
                    }) {
                        Text("Finish Capture")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.blue))
                    }
                }
                .padding(.horizontal, 20)
            } else {
                HStack {
                    Button("Cancel") {
                        appModel.objectCaptureSession?.cancel()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                    
                    Button("Start Capture") {
                        startCapture()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Capsule().fill(Color.blue))
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    private func setupSession() {
        // Initialize preview system
        previewSystemManager.initialize(in: session)
    }
    
    private func cleanupSession() {
        previewSystemManager.cleanup()
    }
    
    private func startCapture() {
        isCapturing = true
        session.startCapturing()
    }
    
    private func endCapture() {
        isCapturing = false
        session.finish()
    }
}

// MARK: - Preview System Manager
class PreviewSystemManager: ObservableObject {
    @Published var previewSystem: RealtimeMeshPreviewSystem?
    private var cancellables = Set<AnyCancellable>()
    
    func initialize(in session: ObjectCaptureSession) {
        // Find ARView after a short delay to ensure view hierarchy is set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController,
               let arView = self.findARView(in: rootViewController.view) {
                
                self.previewSystem = RealtimeMeshPreviewSystem(arView: arView)
            }
        }
    }
    
    func cleanup() {
        previewSystem?.cleanup()
        previewSystem = nil
    }
    
    private func findARView(in view: UIView) -> ARView? {
        if let arView = view as? ARView {
            return arView
        }
        
        for subview in view.subviews {
            if let arView = findARView(in: subview) {
                return arView
            }
        }
        
        return nil
    }
}

// MARK: - Guide Overlay
struct GuideOverlay: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Scanning Guide")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                guideRow(icon: "arrow.left.and.right", text: "Move slowly around the surface")
                guideRow(icon: "ruler", text: "Keep device 40-60cm from surface")
                guideRow(icon: "light.max", text: "Ensure good lighting")
                guideRow(icon: "camera.metering.center.weighted", text: "Maintain steady motion")
            }
            
            Button("Got it") {
                withAnimation {
                    isVisible = false
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(15)
        .padding()
    }
    
    private func guideRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 30)
            
            Text(text)
                .foregroundColor(.white)
        }
    }
}
