//
//  CapturePrimaryView.swift
//  Surface Capture App
//

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

struct CustomCaptureOverlay: View {
    let captureState: ObjectCaptureSession.CaptureState
    let trackingQuality: TrackingQualityStatus
    
    var body: some View {
        VStack {
            // Custom coaching hints
            if case .detecting = captureState {
                CoachingHint(
                    icon: "camera.viewfinder",
                    message: "Move closer to the surface"
                )
                .transition(.opacity)
            }
            
            // Quality indicator
            QualityIndicatorView(quality: trackingQuality)
                .padding(.top)
            
            // Capture progress
            if case .capturing = captureState {
                CaptureProgressView()
                    .transition(.slide)
            }
        }
        .animation(.easeInOut, value: captureState)
    }
}

struct CoachingHint: View {
    let icon: String
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
            Text(message)
                .font(.headline)
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
}

struct QualityIndicatorView: View {
    let quality: TrackingQualityStatus
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(qualityColor)
                .frame(width: 12, height: 12)
            
            Text(qualityMessage)
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(15)
    }
    
    private var qualityColor: Color {
        switch quality {
        case .normal: return .green
        case .limited: return .yellow
        case .notAvailable: return .red
        }
    }
    
    private var qualityMessage: String {
        switch quality {
        case .normal: return "Good Tracking"
        case .limited: return "Move Slower"
        case .notAvailable: return "Lost Tracking"
        }
    }
}

struct CaptureProgressView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.circle.fill")
                .font(.system(size: 24))
            Text("Capturing Surface...")
                .font(.headline)
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
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
    @State private var isSessionReady = false
    
    // Add state for image picker
    @State private var isImagePickerPresented: Bool = false
    
    private let trackingMonitor = EnhancedTrackingMonitor()
    
    var body: some View {
        ZStack {
            if isSessionReady {
                // Only show ObjectCaptureView once the session is confirmed ready
                ObjectCaptureView(session: session)
                    .hideObjectReticle(true)
                    .overlay(alignment: .bottom) {
                        controlsOverlay
                    }
                    .overlay(alignment: .top) {
                        if isCapturing {
                            CustomCaptureOverlay(
                                captureState: session.state,
                                trackingQuality: trackingQuality
                            )
                            .padding(.top, 44)
                        }
                    }
                    .overlay(alignment: .center) {
                        if isInitializing {
                            InitializationView(error: initializationError)
                        } else if showPerformanceWarning {
                            WarningBanner(message: "Performance issues detected - try moving slower")
                        }
                    }
            } else {
                // Show loading view while session initializes
                VStack {
                    ProgressView("Preparing camera...")
                    Text("Please wait while AR tracking initializes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .onAppear {
            validateAndSetupSession()
        }
        .onDisappear {
            cleanupSession()
        }
        .alert("Tracking Warning", isPresented: $showTrackingWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try moving the camera more slowly and ensure good lighting")
        }
        .sheet(isPresented: $isImagePickerPresented) {
            ImagePicker(selectedImage: $appModel.selectedImage)
                .onDisappear {
                    if appModel.selectedImage != nil {
                        // Use the centralized handling
                        appModel.handleSelectedImage(appModel.selectedImage)
                    }
                }
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
                    // Add Image Picker Button
                    Button(action: {
                        isImagePickerPresented = true
                    }) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text("Image")
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Capsule().fill(Color.green))
                    }
                    .padding(.horizontal, 4)
                    
                    Button("Start Capture") {
                        startCapture()
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Capsule().fill((isCameraReady && !isInitializing) ? Color.blue : Color.gray.opacity(0.6)))
                    .opacity((isCameraReady && !isInitializing) ? 1.0 : 0.7)
                    .disabled(!(isCameraReady && !isInitializing))
                }
            }
        }
        .padding(.bottom, 40)
    }
    
    // MARK: - Helper Methods
    
    private func validateAndSetupSession() {
        // Ensure the session is properly initialized before showing the view
        isSessionReady = false
        isCameraReady = false
        isInitializing = true
        
        // Make sure the session has been started and is in a valid state
        // Commenting out this block properly with a single-line comment style
        // if session.state == .failed {
        //     print("Session already in failed state on appearance")
        //     initializationError = CameraError.initializationTimeout
        //     return
        // }
        
        // Start with a task to monitor the session state
        Task {
            // Add a timeout to prevent indefinite waiting
            let timeout = Task {
                try await Task.sleep(for: .seconds(1.8))
                await MainActor.run {
                    // Force readiness if timeout occurs to avoid blocking the user
                    if !isSessionReady {
                        print("Session readiness timeout - forcing readiness")
                        isSessionReady = true
                        isCameraReady = true
                        isInitializing = false
                    }
                }
            }
            
            // Monitor session state changes to detect when it's ready
            do {
                // Make the await call itself throw with 'try' before it
                let stateUpdates = try session.stateUpdates
                
                for await state in stateUpdates {
                    await MainActor.run {
                        print("Session state updated to: \(state)")
                        
                        // Use a switch statement for proper pattern matching with multiple cases
                        switch state {
                        case .ready, .detecting, .capturing:
                            // These are the states we consider "ready"
                            isSessionReady = true
                            isCameraReady = true
                            isInitializing = false
                            timeout.cancel() // Cancel the timeout once ready
                            
                        case .failed(let error):
                            print("Session failed: \(error)")
                            initializationError = error
                            isSessionReady = true // Show the view with error
                            isInitializing = false
                            timeout.cancel()
                            
                        default:
                            // For other states like initializing, we don't change the ready state
                            break
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("Error monitoring session state: \(error)")
                    isSessionReady = true
                    isInitializing = false
                    timeout.cancel()
                }
            }
        }
        
        // Setup UI applications and tracking monitor
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start tracking monitor after confirming the session is valid
        trackingMonitor.startMonitoring(session: session) { quality, stats in
            Task { @MainActor in
                self.trackingQuality = quality
                print("Tracking Quality: \(quality)")
                self.showPerformanceWarning = stats.hasResourceConstraints
            }
        }
        
        // Listen for ARKit session notifications
        setupARKitNotifications()
    }
    
    private func setupARKitNotifications() {
        // Listen for ARKit tracking state changes
        NotificationCenter.default.addObserver(
            forName: .ARSessionTrackingStateChanged,
            object: nil,
            queue: .main) { _ in
                if !self.isCameraReady {
                    print("AR tracking state changed")
                    _ = self.checkARTrackingStatus() // Use underscore to explicitly ignore result
                }
        }
        
        // Listen for ARKit session activation
        NotificationCenter.default.addObserver(
            forName: .ARSessionDidBecomeActive,
            object: nil,
            queue: .main) { _ in
                print("AR Session became active")
                self.isCameraReady = true
                self.isInitializing = false
        }
        
        // Memory warning monitoring
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main) { _ in
                self.showPerformanceWarning = true
        }
    }
    
    private func checkARTrackingStatus() -> Bool {
        // We can't directly access ARView in a SwiftUI view
        // Instead, make a reasonable assumption based on session state
        if session.state == .ready || session.state == .detecting {
            print("Session appears to be in a ready state")
            self.isCameraReady = true
            self.isInitializing = false
            return true
        }
        return false
    }
    
    private func setupSession() {
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start with disabled button
        isCameraReady = false
        isInitializing = true
        
        // Start tracking monitor
        trackingMonitor.startMonitoring(session: session) { quality, stats in
            Task { @MainActor in
                self.trackingQuality = quality
                print("********** Tracking Quality: \(quality)")
                self.showPerformanceWarning = stats.hasResourceConstraints
            }
        }
        
        // 1. APPROACH: Listen for ARKit tracking state changes
        NotificationCenter.default.addObserver(
            forName: .ARSessionTrackingStateChanged,
            object: nil,
            queue: .main) { _ in
                _ = self.checkARTrackingStatus() // Using underscore to explicitly ignore result
                print("Tracking status: \(self.checkARTrackingStatus())")
        }
        
        // 2. APPROACH: Listen for ARKit session running notifications
        NotificationCenter.default.addObserver(
            forName: .ARSessionDidBecomeActive,
            object: nil,
            queue: .main) { _ in
                print("AR Session became active")
                self.isCameraReady = true
                self.isInitializing = false
        }
        
        // 3. APPROACH: Continue monitoring session state updates directly
        Task {
            do {
                for try await state in session.stateUpdates {
                    await MainActor.run {
                        print("ObjectCaptureSession state: \(state)")
                        // When we see a ready state, enable the capture button
                        if case .ready = state {
                            self.isCameraReady = true
                            self.isInitializing = false
                        }
                    }
                }
            }
        }
        
        // 4. APPROACH: Memory warning monitoring (as you had before)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main) { _ in
                //showPerformanceWarning = true
        }
        
        // 5. APPROACH: Fallback timer after a reasonable delay
        //DispatchQueue.main.asyncAfter(deadline: .now()) {
            // Using explicit comparison instead of negation to avoid syntax issues
            if self.isCameraReady == false {
                print("Fallback timer activating camera readiness")
                self.isCameraReady = true
                self.isInitializing = false
            }
        //}
        

    }

    private func checkSessionReady() {
        // Check immediately, then at increasing intervals
        let checkIntervals = [0.5, 1.0, 2.0, 3.0, 5.0]
        
        for (index, interval) in checkIntervals.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                if session.state == .ready || session.state == .detecting {
                    isCameraReady = true
                    isInitializing = false
                } else if index == checkIntervals.count - 1 {
                    // Last attempt, session still not ready
                    if !isCameraReady {
                        isCameraReady = true  // Just enable it anyway at this point
                        isInitializing = false
                    }
                }
            }
        }
    }

    private func startCameraInitialization() {
        isInitializing = true
        
        /*
         // Add timeout just in case
         Task { @MainActor in
         //try? await Task.sleep(for: .seconds(0))
         if !isCameraReady {
         initializationError = CameraError.initializationTimeout
         }
         }
         */
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCameraReady = true
            isInitializing = false
        }
        // Make camera ready immediately - this worked in the original code
        
    }
    
    private func cleanupSession() {
        UIApplication.shared.isIdleTimerDisabled = false
        trackingMonitor.stopMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startCapture() {
        // First check if camera is ready and there are no performance warnings
        guard isCameraReady && !showPerformanceWarning else { return }
        
        print("Session state before starting capture: \(session.state)")
        
        // Additional validation to ensure session is in a valid state for capturing
        guard session.state == .ready || session.state == .detecting else {
            // Show a user-facing message about the session not being ready
            let message = "Waiting for camera to initialize. Please try again in a moment."
            appModel.messageList.add(message)
            
            // Schedule removal of the message after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                appModel.messageList.remove(message)
            }
            return
        }
        
        // Start the capture session
        session.startCapturing()
        isCapturing = true
        
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

extension Notification.Name {
    static let ARSessionTrackingStateChanged = Notification.Name("ARSessionTrackingStateChanged")
    static let ARSessionDidBecomeActive = Notification.Name("ARSessionDidBecomeActive")
}
