import SwiftUI
import RealityKit
import ARKit
import Combine

struct PhotogrammetryCaptureView: View {
    @EnvironmentObject var appModel: AppDataModel
    @StateObject private var captureState = CaptureStateModel()
    
    private let arView = ARView(frame: .zero)
    private var focusEntity: FocusEntity?
    private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ZStack {
            ARViewContainer(arView: arView, captureState: captureState)
                .ignoresSafeArea()
                .onAppear {
                    setupAR()
                }
            
            if captureState.isCapturing {
                CaptureOverlay(
                    coverage: captureState.coverage,
                    qualityMetrics: captureState.qualityMetrics
                )
            }
            
            VStack {
                Spacer()
                
                if captureState.isCapturing {
                    Button(action: {
                        finishCapture()
                    }) {
                        Text("Finish Capture")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Capsule().fill(Color.blue))
                    }
                    .padding(.bottom, 40)
                } else {
                    HStack {
                        Button("Cancel") {
                            appModel.state = .restart
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
                        .disabled(!captureState.isReady)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .alert("Capture Error", isPresented: $captureState.showError) {
            Button("OK") {}
        } message: {
            Text(captureState.errorMessage)
        }
    }
    
    private func setupAR() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        
        arView.session.run(config)
        
        // Create focus entity
        focusEntity = FocusEntity()
        if let entity = focusEntity {
            arView.scene.addAnchor(AnchorEntity())
            arView.scene.anchors.first?.addChild(entity)
            
            // Handle plane detection
            entity.onPlaneDetected = { transform in
                if captureState.isCapturing {
                    captureState.addCapturePoint(transform)
                }
            }
        }
        
        // Setup frame processing
        arView.session.delegate = captureState
        
        captureState.isReady = true
    }
    
    private func startCapture() {
        guard let folderManager = CaptureFolderManager() else {
            captureState.showError(message: "Failed to create capture folders")
            return
        }
        
        captureState.startCapture(imagesFolder: folderManager.imagesFolder)
        appModel.scanFolderManager = folderManager
    }
    
    private func finishCapture() {
        captureState.finishCapture()
        appModel.state = .prepareToReconstruct
    }
}

class CaptureStateModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var isReady = false
    @Published var isCapturing = false
    @Published var coverage: Float = 0
    @Published var qualityMetrics = CaptureQualityMetrics()
    @Published var showError = false
    @Published var errorMessage = ""
    
    private var capturePoints: [simd_float4x4] = []
    private var imagesFolder: URL?
    private var frameCount = 0
    private let frameInterval = 10 // Capture every 10th frame
    
    func startCapture(imagesFolder: URL) {
        self.imagesFolder = imagesFolder
        isCapturing = true
        capturePoints.removeAll()
        coverage = 0
    }
    
    func finishCapture() {
        isCapturing = false
    }
    
    func addCapturePoint(_ transform: simd_float4x4) {
        capturePoints.append(transform)
        coverage = min(Float(capturePoints.count) / 100.0, 1.0)
    }
    
    func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    // ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isCapturing else { return }
        
        frameCount += 1
        guard frameCount % frameInterval == 0,
              let imagesFolder = imagesFolder else { return }
        
        // Update quality metrics
        qualityMetrics.motionSteadiness = calculateMotionSteadiness(frame)
        qualityMetrics.depthQuality = calculateDepthQuality(frame)
        qualityMetrics.surfaceCoverage = coverage
        
        // Capture frame if quality is good
        if qualityMetrics.motionSteadiness > 0.7 && qualityMetrics.depthQuality > 0.7 {
            captureFrame(frame, to: imagesFolder)
        }
    }
    
    private func captureFrame(_ frame: ARFrame, to folder: URL) {
        let image = frame.capturedImage
        let pixelBuffer = image
        
        guard let cgImage = createCGImage(from: pixelBuffer) else { return }
        
        let filename = "frame_\(frameCount).jpg"
        let fileURL = folder.appendingPathComponent(filename)
        
        do {
            try saveCGImage(cgImage, to: fileURL)
        } catch {
            showError(message: "Failed to save image: \(error.localizedDescription)")
        }
    }
    
    private func calculateMotionSteadiness(_ frame: ARFrame) -> Float {
        // Calculate based on camera movement
        let currentTransform = frame.camera.transform
        let rotationRate = frame.camera.eulerAngles.length
        let translationRate = simd_length(currentTransform.columns.3.xyz)
        
        let steadiness = 1.0 - min(rotationRate + translationRate, 1.0)
        return Float(steadiness)
    }
    
    private func calculateDepthQuality(_ frame: ARFrame) -> Float {
        guard let depthMap = frame.sceneDepth?.depthMap else { return 0 }
        
        // Calculate average confidence from depth data
        var confidence: Float = 0
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        if let baseAddress = CVPixelBufferGetBaseAddress(depthMap) {
            let buffer = baseAddress.assumingMemoryBound(to: Float32.self)
            let count = width * height
            
            for i in 0..<count {
                confidence += buffer[i]
            }
            confidence /= Float(count)
        }
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        
        return confidence
    }
    
    private func createCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }
    
    private func saveCGImage(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) else {
            throw NSError(domain: "ImageSaving", code: -1, userInfo: nil)
        }
        
        CGImageDestinationAddImage(destination, image, nil)
        
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ImageSaving", code: -1, userInfo: nil)
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    let arView: ARView
    let captureState: CaptureStateModel
    
    func makeUIView(context: Context) -> ARView {
        arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

struct CaptureOverlay: View {
    let coverage: Float
    let qualityMetrics: CaptureQualityMetrics
    
    var body: some View {
        VStack {
            HStack {
                QualityIndicator(
                    icon: "camera.metering.center.weighted",
                    value: qualityMetrics.depthQuality,
                    label: "Depth"
                )
                
                QualityIndicator(
                    icon: "hand.raised.slash",
                    value: qualityMetrics.motionSteadiness,
                    label: "Stability"
                )
                
                QualityIndicator(
                    icon: "square.on.square",
                    value: coverage,
                    label: "Coverage"
                )
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
            
            Spacer()
        }
        .padding(.top, 40)
    }
}
