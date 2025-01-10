import SwiftUI
import RealityKit
import ARKit
import os
import Combine

// MARK: - Supporting Types
enum TrackingQualityStatus: Equatable {
    case normal
    case limited
    case notAvailable
}

enum CaptureQualityStatus {
    case excellent
    case good
    case limited(reason: LimitedReason)
    case notAvailable
    
    enum LimitedReason {
        case poorDepth
        case excessiveMotion
        case insufficientFeatures
        case lowLight
    }
}

struct CaptureQualityMetrics {
    var isDepthAvailable: Bool = false
    var depthQuality: Float = 0.0
    var motionSteadiness: Float = 1.0
    var processedAreaPercentage: Float = 0.0
    var surfaceCoverage: Float = 0.0
    var hasResourceConstraints: Bool = false
}

struct CaptureRegion: Hashable {
    let x: Int
    let y: Int
    let confidence: Float
}

enum CameraError: LocalizedError {
    case initializationTimeout
    case trackingLost
    
    var errorDescription: String? {
        switch self {
        case .initializationTimeout:
            return "Camera initialization timed out"
        case .trackingLost:
            return "Camera tracking lost - try moving slower"
        }
    }
}

struct CameraStats {
    var droppedFrameCount: Int = 0
    var hasResourceConstraints: Bool = false
}

actor EnhancedTrackingMonitorState {
    private var metrics = CaptureQualityMetrics()
    private var processedRegions: Set<CaptureRegion> = []
    private var previousCameraTransform: simd_float4x4?
    private var motionSamples: [Float] = []
    private var stats = CameraStats()
    
    func updateMetrics(hasResourceConstraints: Bool, isDepthAvailable: Bool = false) {
        metrics.hasResourceConstraints = hasResourceConstraints
        metrics.isDepthAvailable = isDepthAvailable
        stats.hasResourceConstraints = hasResourceConstraints
    }
    
    func getStatus() -> TrackingQualityStatus {
        if metrics.hasResourceConstraints || !metrics.isDepthAvailable {
            return .notAvailable
        }
        
        if metrics.motionSteadiness < 0.4 || metrics.depthQuality < 0.3 {
            return .limited
        }
        
        return .normal
    }
    
    func getStats() -> CameraStats {
        stats
    }
    
    func updateMotionSteadiness(_ value: Float) {
        metrics.motionSteadiness = value
    }
    
    func reset() {
        metrics = CaptureQualityMetrics()
        processedRegions.removeAll()
        previousCameraTransform = nil
        motionSamples.removeAll()
        stats = CameraStats()
    }
}

@available(iOS 17.0, *)
class EnhancedTrackingMonitor: NSObject, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.example.SurfaceCapture",
        category: "EnhancedTrackingMonitor"
    )
    
    private let state = EnhancedTrackingMonitorState()
    private var objectCaptureSession: ObjectCaptureSession?
    private var monitoringTask: Task<Void, Never>?
    private let regionSize: CGFloat = 50.0
    private let motionSampleCount = 10

    func startMonitoring(
        session: ObjectCaptureSession,
        completion: @escaping @Sendable (TrackingQualityStatus, CameraStats) -> Void
    ) {
        objectCaptureSession = session

        // Monitor session state changes
        monitoringTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                for try await state in await session.stateUpdates {
                    try await self.processStateUpdate(state)
                    let trackingStatus = await self.state.getStatus()
                    let currentStats = await self.state.getStats()
                    
                    await MainActor.run {
                        completion(trackingStatus, currentStats)
                    }
                }
            } catch {
                Self.logger.error("State updates error: \(error.localizedDescription)")
            }
        }
    }

    private func processStateUpdate(_ state: ObjectCaptureSession.CaptureState) async throws {
        switch state {
        case .failed(let error):
            Self.logger.error("Capture session failed: \(error.localizedDescription)")
            await self.state.updateMetrics(hasResourceConstraints: true)
            
        case .completed:
            // Handle completion if needed
            break
            
        case .ready, .detecting:
            await self.state.updateMetrics(hasResourceConstraints: false)
            await self.state.updateMotionSteadiness(1.0)
            
        case .initializing:
            await self.state.updateMotionSteadiness(0.5)
            
        default:
            break
        }
    }

    func stopMonitoring() {
        Task { [weak self] in
            guard let self = self else { return }
            
            monitoringTask?.cancel()
            monitoringTask = nil
            objectCaptureSession = nil
            await state.reset()
        }
    }
}

private struct InitializationView: View {
    let error: Error?
    
    var body: some View {
        VStack(spacing: 16) {
            if let error = error {
                Text("Initialization Error")
                    .font(.headline)
                Text(error.localizedDescription)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView("Initializing Camera...")
                Text("Please wait...")
            }
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
}

private struct WarningBanner: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding()
            .background(Color.red.opacity(0.8))
            .cornerRadius(10)
    }
}

// MARK: - Main View
@available(iOS 17.0, *)
struct CapturePrimaryView: View {
    @EnvironmentObject var appModel: AppDataModel
    var session: ObjectCaptureSession
    
    @State private var showInfo: Bool = false
    @State private var isCapturing = false
    @State private var isCameraReady = false
    @State private var isInitializing = true
    @State private var initializationError: Error?
    @State private var trackingQuality: TrackingQualityStatus = .normal
    @State private var showTrackingWarning = false
    @State private var showPerformanceWarning = false
    
    private let trackingMonitor = EnhancedTrackingMonitor() //TrackingQualityMonitor()
    
    var body: some View {
        ZStack {
            if isCameraReady {
                ObjectCaptureView(session: session)
                    .overlay(alignment: .bottom) {
                        controlsOverlay
                    }
                    .overlay(alignment: .top) {
                        if isCapturing {
                            //statusOverlay
                        }
                    }
                    .overlay(alignment: .center) {
                        if showPerformanceWarning {
                            WarningBanner(message: "Performance issues detected - try moving slower")
                        }
                    }
            } else {
                InitializationView(error: initializationError)
            }
        }
        .onAppear {
            setupSession()
        }
        .onDisappear {
            cleanupSession()
        }
        .alert("Tracking Warning", isPresented: $showTrackingWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try moving the camera more slowly and ensure good lighting")
        }
    }
    
    // MARK: - View Components
    
    private var controlsOverlay: some View {
        VStack(spacing: 20) {
            if session.state == .capturing {
                Button(action: {
                    withAnimation {
                        session.finish()
                    }
                }) {
                    Text("Finish Capture")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Capsule().fill(Color.blue))
                }
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
                    .disabled(!isCameraReady || showPerformanceWarning)
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    private var statusOverlay: some View {
        VStack(spacing: 8) {
            Text(captureStatusMessage)
                .font(.headline)
            
            if trackingQuality != .normal {
                Text(trackingQualityMessage)
                    .foregroundColor(.yellow)
            }
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .padding(.top, 40)
    }
    
    // MARK: - Helper Methods
    
    private func setupSession() {
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Monitor memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main) { _ in
                showPerformanceWarning = true
            }
        
        startCameraInitialization()
    }
    
    private func cleanupSession() {
        UIApplication.shared.isIdleTimerDisabled = false
        trackingMonitor.stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startCameraInitialization() {
            isInitializing = true
            
            // Add timeout for initialization
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if !isCameraReady {
                    initializationError = CameraError.initializationTimeout
                }
            }
            
            // Setup session state monitoring
            trackingMonitor.startMonitoring(session: session) { quality, stats in
                Task { @MainActor in
                    trackingQuality = quality
                    showPerformanceWarning = stats.hasResourceConstraints
                    
                    if quality == .limited {
                        showTrackingWarning = true
                    }
                }
            }
            
            // Allow time for camera initialization
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                isCameraReady = true
                isInitializing = false
            }
        }
    
    private func startCapture() {
        guard isCameraReady && !showPerformanceWarning else { return }
        
        isCapturing = true
        session.startCapturing()
        
        // Reset warning state
        showPerformanceWarning = false
    }
    
    private var captureStatusMessage: String {
        if showPerformanceWarning {
            return "Performance Issues Detected"
        } else {
            switch trackingQuality {
            case .normal:
                return "Move slowly across the surface"
            case .limited:
                return "Move camera more slowly"
            case .notAvailable:
                return "Tracking lost"
            }
        }
    }
    
    private var trackingQualityMessage: String {
        switch trackingQuality {
        case .normal:
            return ""
        case .limited:
            return "⚠️ Limited tracking quality"
        case .notAvailable:
            return "❌ Tracking lost"
        }
    }
}
