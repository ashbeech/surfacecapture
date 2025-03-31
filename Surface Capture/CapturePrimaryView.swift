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
        // Debug output
        print("Resource Constraints: \(metrics.hasResourceConstraints)")
        print("Depth Available: \(metrics.isDepthAvailable)")
        print("Motion Steadiness: \(metrics.motionSteadiness)")
        print("Depth Quality: \(metrics.depthQuality)")
        
        // Only consider truly critical factors for tracking loss
        if metrics.hasResourceConstraints {
            return .notAvailable
        }
        
        // If motion steadiness is very poor, consider it limited tracking
        if metrics.motionSteadiness < 0.4 {
            return .limited
        }
        
        // Even if depth data isn't optimal, consider tracking normal
        // This is a key change - we don't require depth data for basic tracking
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
            
        case .capturing:
            // Ensure resource constraints get reset when in capturing state
            await self.state.updateMetrics(hasResourceConstraints: false, isDepthAvailable: true)
            await self.state.updateMotionSteadiness(1.0)
            
        case .ready, .detecting:
            // Ensure resource constraints get reset when in ready or detecting state
            await self.state.updateMetrics(hasResourceConstraints: false)
            await self.state.updateMotionSteadiness(1.0)
            
        case .initializing:
            await self.state.updateMotionSteadiness(0.5)
            
        default:
            // Add a log to check for unexpected states
            print("Unexpected state: \(state)")
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

@available(iOS 17.0, *)
struct CaptureProgressIndicator: View {
    let imageCount: Int
    let minRequired: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Camera icon with count
            HStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                
                Text("\(imageCount)")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .cornerRadius(6)
            
            // Progress bar
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 100, height: 8)
                
                // Fill
                Capsule()
                    .fill(progressColor)
                    .frame(width: CGFloat(min(imageCount, minRequired)) / CGFloat(minRequired) * 100, height: 8)
                    .animation(.easeInOut, value: imageCount)
            }
            
            // Indication text based on progress
            Text(statusText)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(10)
    }
    
    private var progressColor: Color {
        let progress = Double(imageCount) / Double(minRequired)
        switch progress {
        case 0..<0.5: return .red
        case 0.5..<1.0: return .orange
        default: return .green
        }
    }
    
    private var statusText: String {
        if imageCount < minRequired {
            return "Need \(minRequired - imageCount) more"
        } else if imageCount < minRequired * 2 {
            return "Good"
        } else {
            return "Excellent"
        }
    }
}

@available(iOS 17.0, *)
struct CustomCaptureOverlay: View {
    let captureState: ObjectCaptureSession.CaptureState
    let trackingState: ObjectCaptureSession.Tracking
    let imageCount: Int
    let minRequiredImages: Int
    
    var body: some View {
        VStack {
            // Quality indicator for tracking state
            if case .limited(let reason) = trackingState {
                TrackingQualityIndicator(
                    tracking: trackingState,
                    reason: reason
                )
                .padding(.bottom, 8)
                .transition(.opacity)
            }
            
            // Capture progress
            if case .capturing = captureState {
                CaptureProgressView()
                    .transition(.slide)
                    .padding(.top, 8)
            }
        }
        .animation(.easeInOut, value: captureState)
        .animation(.easeInOut, value: imageCount)
        .animation(.easeInOut, value: trackingState)
    }
}

@available(iOS 17.0, *)
struct TrackingQualityIndicator: View {
    let tracking: ObjectCaptureSession.Tracking
    let reason: ObjectCaptureSession.Tracking.Reason?
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            // Status message
            Text(statusMessage)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(15)
    }
    
    private var statusColor: Color {
        switch tracking {
        case .normal:
            return .green
        case .limited:
            return .yellow
        case .notAvailable:
            return .red
        @unknown default:
            return .orange
        }
    }
    
    private var statusMessage: String {
        switch tracking {
        case .normal:
            return "Good Tracking"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "Move Camera Slower"
            case .insufficientFeatures:
                return "Need More Features"
            case .initializing:
                return "Initializing Tracking"
            case .relocalizing:
                return "Relocalizing"
            @unknown default:
                return "Limited Tracking"
            }
        case .notAvailable:
            return "No Tracking Available"
        @unknown default:
            return "Check Tracking Status"
        }
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
    
    // User help
    @ObservedObject var onboardingManager: OnboardingManager
    
    // Session state
    @State private var showInfo: Bool = false
    @State private var isCapturing = false
    @State private var isCameraReady = false
    @State private var isInitializing = true
    @State private var initializationError: Error?
    @State private var isSessionReady = false
    
    // Tracking state
    @State private var sessionTracking: ObjectCaptureSession.Tracking = .normal
    @State private var showTrackingWarning = false
    @State private var trackingMonitorTask: Task<Void, Never>?
    
    // Image picker state
    @State private var isImagePickerPresented: Bool = false
    @State private var isInImagePickerFlow: Bool = false
    
    // Image count tracking
    @State private var capturedImageCount: Int = 0
    @State private var imageCountTimer: Timer?
    
    // Legacy tracking monitor - kept for backward compatibility
    private let trackingMonitor = EnhancedTrackingMonitor()
    
    @State private var isTransitioning = false
    
    // First, let's add a computed property to determine the appropriate loading message
    private var loadingMessage: (title: String, description: String) {
        if isImagePickerPresented {
            return ("Pulling up photo library", "Opening image selector...")
        } else if isInImagePickerFlow && !isTransitioning {
            return ("Returning to camera", "Please wait...")
        } else if isInitializing {
            return ("Preparing AR camera", "Setting up tracking...")
        } else if isTransitioning {
            return ("Processing", "Preparing selected image...")
        } else {
            return ("Preparing...", "Please wait a moment")
        }
    }
    
    private func cleanupAndResetState() {
        // Stop all ongoing processes
        stopImageCountTimer()
        trackingMonitorTask?.cancel()
        trackingMonitorTask = nil
        
        // Stop the session if it's running
        if isCapturing {
            session.cancel()  // Cancel instead of finish to abort the capture
        }
        
        // Reset view state variables
        isCapturing = false
        capturedImageCount = 0
        showTrackingWarning = false
        
        // Reset tracking and quality metrics
        sessionTracking = .normal
        
        // Restart camera and session preparation
        isSessionReady = true
        isCameraReady = true
        isInitializing = false
        
        // Remove any temporary files if needed
        if let folderManager = appModel.scanFolderManager {
            do {
                // Only delete image files, keep the folder structure
                let imageFiles = try FileManager.default.contentsOfDirectory(
                    at: folderManager.imagesFolder,
                    includingPropertiesForKeys: nil
                )
                
                for file in imageFiles {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                print("Error cleaning up temporary files: \(error)")
            }
        }
        
        // Force UI update
        withAnimation {
            appModel.state = .ready
        }
    }
    
    var body: some View {
        ZStack {
            if isSessionReady && !isTransitioning && !isImagePickerPresented && !isInImagePickerFlow {
                ObjectCaptureView(session: session)
                    .hideObjectReticle(true)
                    .overlay(alignment: .topLeading) {
                        // Back button with circular styling
                        if isCapturing {
                            Button(action: {
                                cleanupAndResetState()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            .padding(.leading, 20)
                            .transition(.opacity)
                            .animation(.easeInOut, value: isCapturing)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        // Bottom controls with fixed position
                        enhancedControlsOverlay
                    }
                    .overlay(alignment: .topTrailing) {
                        // Help button
                        Button(action: {
                            onboardingManager.resetOnboarding()
                        }) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .background(Color.black.opacity(0.7))
                        .clipShape(Circle())
                        .padding(.trailing, 20)
                        .padding(.top, 0)
                    }
            } else {
                // Show loading view while session initializes
                VStack {
                    ProgressView(loadingMessage.title)
                    Text(loadingMessage.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            
            // Add the transition overlay on top of everything when transitioning
            if isTransitioning {
                TransitionOverlay()
                    .animation(.easeInOut, value: isTransitioning)
            }
        }
        .onAppear {
            validateAndSetupSession()
            startImageCountTimer()
            setupTrackingUpdates()
        }
        .onDisappear {
            cleanupSession()
        }
        .alert("Tracking Warning", isPresented: $showTrackingWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trackingWarningMessage)
        }
        .sheet(isPresented: $isImagePickerPresented, onDismiss: {
            // Don't immediately reset isInImagePickerFlow when dismissed
            if appModel.selectedImage != nil {
                isTransitioning = true
                // Keep isInImagePickerFlow true to prevent ObjectCaptureView from showing
                appModel.handleSelectedImage(appModel.selectedImage)
            } else {
                // Only reset the flow if no image was selected
                isInImagePickerFlow = false
            }
        }) {
            ImagePicker(selectedImage: $appModel.selectedImage)
        }
    }
    
    // MARK: - Enhanced Controls Overlay
    
    // This computes whether enough images have been captured for a good model
    private var hasEnoughCaptures: Bool {
        return capturedImageCount >= AppDataModel.minNumImages
    }
    
    // Calculate capture quality based on current session data using official session tracking
    private var captureQuality: CaptureQuality {
        // First check if we have enough captures - this is the primary requirement
        
        if !hasEnoughCaptures {
            return .insufficient
        }
        
        // We have enough images, so check tracking quality
        switch sessionTracking {
        case .normal:
            return .ready
        case .limited:
            // Still allow completion with limited tracking, but show warning
            return .ready
        case .notAvailable:
            // Only block completion if tracking is completely unavailable
            return .noTracking
        @unknown default:
            // For future unknown tracking states, assume limited tracking
            return .limitedTracking
        }
    }
    
    private var trackingWarningMessage: String {
        if case .limited(let reason) = sessionTracking {
            switch reason {
            case .excessiveMotion:
                return "Camera is moving too quickly. Please move more slowly to improve tracking."
            case .insufficientFeatures:
                return "Not enough visual features detected. Try moving to an area with more visual details."
            case .initializing:
                return "Tracking system is still initializing. Please wait a moment."
            case .relocalizing:
                return "Relocalizing"
            @unknown default:
                return "Tracking quality is limited. Try adjusting your environment."
            }
        } else if case .notAvailable = sessionTracking {
            return "Tracking is not available. Try moving to a well-lit area with more visual features."
        } else {
            return "Try moving the camera more slowly and ensure good lighting."
        }
    }
    
    private struct TransitionOverlay: View {
        var body: some View {
            ZStack {
                // Dark semi-transparent background to cover the old UI
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
                
                // Loading indicator
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Processing...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(Color.black.opacity(0.6))
                .cornerRadius(15)
            }
            .transition(.opacity)
        }
    }
    
    struct CaptureProgressButton: View {
        // Image capturing progress
        let imageCount: Int
        let minRequired: Int
        
        // Button state
        let isEnabled: Bool
        let isCapturingMode: Bool // This tracks if the session is in capturing mode
        let action: () -> Void
        
        var body: some View {
            GeometryReader { geometry in
                Button(action: {
                    // Execute action if either:
                    // 1. Not in capturing mode yet (initial state)
                    // 2. Has enough captures (completion state)
                    if !isCapturingMode || hasEnoughCaptures {
                        action()
                    }
                }) {
                    ZStack(alignment: .leading) {
                        // Button background - solid color even when disabled
                        Capsule()
                            .fill(buttonColor)
                            .frame(width: geometry.size.width)
                        
                        // Progress overlay (only shown during capture with images)
                        if isCapturingMode && !hasEnoughCaptures && imageCount > 0 {
                            Capsule()
                                .fill(progressColor)
                                .frame(width: progressWidth(totalWidth: geometry.size.width))
                        }
                        
                        // Button content - centered in the button
                        HStack {
                            Spacer()
                            // Icon changes based on state
                            if hasEnoughCaptures {
                                // Enough images captured
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }else{
                                // Initial state
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                            
                            // Text changes based on state
                            if !isCapturingMode {
                                // Initial state
                                Text("Scan Surface")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            } else if hasEnoughCaptures {
                                // Enough images captured
                                Text("Finish Scan")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            } else if imageCount == 0 {
                                // After tap but before first image
                                Text("Scanning...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            } else {
                                // Once images start being captured
                                Text("\(imageCount)/\(minRequired)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                }
                .buttonStyle(PlainButtonStyle()) // Use PlainButtonStyle to avoid default button styling
                .allowsHitTesting((isCapturingMode && hasEnoughCaptures) || (!isCapturingMode && isEnabled))
                .opacity(1.0)
                // Add pulsing effect when ready
                .scaleEffect(hasEnoughCaptures ? 1.0 + (0.03 * sin(Date.timeIntervalSinceReferenceDate * 3)) : 1.0)
                .animation(.easeInOut(duration: 0.3), value: hasEnoughCaptures)
            }
            .frame(height: 54)
        }
        
        // Computed properties
        private var hasEnoughCaptures: Bool {
            return imageCount >= minRequired
        }
        
        private var progress: Double {
            return Double(min(imageCount, minRequired)) / Double(minRequired)
        }
        
        // Progress bar color based on completion level
        private var progressColor: Color {
            switch progress {
            case 0..<0.3: return .red
            case 0.3..<0.7: return .orange
            default: return .yellow
            }
        }
        
        // Button background color based on state - now always solid
        private var buttonColor: Color {
            if hasEnoughCaptures {
                return .green
            } else if isEnabled {
                return isCapturingMode ? Color.blue : .blue
            } else {
                return .gray
            }
        }
        
        // Calculate progress bar width based on actual button width
        private func progressWidth(totalWidth: CGFloat) -> CGFloat {
            return CGFloat(progress) * totalWidth
        }
    }
    
    // A new enum to represent the quality status for UI purposes
    enum CaptureQuality {
        case insufficient      // Not enough images
        case limitedTracking   // Enough images but tracking issues
        case noTracking        // Enough images but severe tracking issues
        case ready             // Enough images and good tracking
        
        var buttonColor: Color {
            switch self {
            case .insufficient: return Color.gray
            case .limitedTracking: return Color.orange
            case .noTracking: return Color.red
            case .ready: return Color.blue
            }
        }
        
        var buttonText: String {
            switch self {
            case .insufficient: return "Capture More"
            case .limitedTracking: return "Improve Tracking"
            case .noTracking: return "Tracking Lost"
            case .ready: return "Finish Capture"
            }
        }
        
        var isEnabled: Bool {
            return self == .ready
        }
        
        var helpText: String? {
            switch self {
            case .insufficient:
                return "Move to capture more images"
            case .limitedTracking:
                return "Move slower for better tracking"
            case .noTracking:
                return "Tracking lost - move camera to recover"
            case .ready:
                return nil
            }
        }
    }
    
    // Enhanced controls overlay with dynamic appearance
    var enhancedControlsOverlay: some View {
        VStack(spacing: 20) {
            ZStack {
                // Initial state with Image button and Join button
                if !isCapturing {
                    HStack {
                        // Image Picker Button
                        Button(action: {
                            appModel.selectedImage = nil
                            isInImagePickerFlow = true
                            isImagePickerPresented = true
                        }) {
                            HStack {
                                Image(systemName: "photo.fill")
                                Text("Add Image")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Capsule().fill(Color.green))
                        }
                        .padding(.horizontal, 4)
                        
                        // Initial state capture button
                        CaptureProgressButton(
                            imageCount: 0,
                            minRequired: AppDataModel.minNumImages,
                            isEnabled: isCameraReady && !isInitializing,
                            isCapturingMode: false,
                            action: {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    startCapture()
                                }
                            }
                        )
                        .frame(width: 180)
                        
                        // Join Streaming Button
                        StreamingJoinButton()
                            .padding(.horizontal, 4)
                    }
                    .transition(.opacity)
                }
                
                // Capturing state - button only, no help text
                if isCapturing && !isTransitioning {
                    CaptureProgressButton(
                        imageCount: capturedImageCount,
                        minRequired: AppDataModel.minNumImages,
                        isEnabled: captureQuality.isEnabled,
                        isCapturingMode: true,
                        action: {
                            withAnimation {
                                if captureQuality.isEnabled {
                                    isTransitioning = true
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                    session.finish()
                                } else {
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.warning)
                                    
                                    if captureQuality == .noTracking || captureQuality == .limitedTracking {
                                        showTrackingWarning = true
                                    }
                                }
                            }
                        }
                    )
                    .frame(width: 220)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isCapturing)
        }
        .padding(.bottom, 33)
    }
    
    // Streaming Join Button specifically for the CapturePrimaryView
    @available(iOS 17.0, *)
    struct StreamingJoinButton: View {
        @State private var showStreamingView = false
        @EnvironmentObject var appModel: AppDataModel
        
        var body: some View {
            Button(action: {
                // Gracefully end the object capture session without triggering errors
                cleanlyEndObjectCaptureSession()
                
                // Show the streaming view
                showStreamingView = true
            }) {
                HStack {
                    Image(systemName: "wifi")
                        .font(.system(size: 16))
                    Text("Join")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.purple))
            }
            .fullScreenCover(isPresented: $showStreamingView, onDismiss: {
                // Resume ObjectCaptureSession when streaming view is dismissed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    appModel.state = .restart
                }
            }) {
                // Present the JoinView as a full-screen cover
                JoinView(onClose: {
                    // This handles when the user explicitly closes the JoinView
                    showStreamingView = false
                })
            }
        }
        
        // Helper function to gracefully end the ObjectCaptureSession without errors
        private func cleanlyEndObjectCaptureSession() {
            
            
            // TODO: SO we are cancelling object capture session on tap of join, but this triggers series of events that will dismiss JoinView.
            // What should happen is we cancel object capture session on tap of join, but this should allow app to enter new state that is
            // designed to handle joining a stream; so elegantly cancel OCS, and allow to reset return on close of JoinView.
            
            // First, remember the current state
            let currentState = appModel.state
            
            // If we're capturing, temporarily set a transitional state to prevent error handling
            if currentState == .capturing {
                // Set to a neutral state first
                appModel.state = .ready
            }
            
            // Check if there's an active session and cancel it
            if let session = appModel.objectCaptureSession {
                // Cancel the session
                session.cancel()
                
                // Clear the reference to prevent further callbacks
                DispatchQueue.main.async {
                    if appModel.objectCaptureSession === session {
                        // Only nil out if it's still the same session
                        // This prevents race conditions
                        appModel.objectCaptureSession = nil
                    }
                }
            }
            
            // Force a restart later to ensure clean state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                appModel.state = .restart
            }
        }
    }

    
    // MARK: - Setup Tracking Updates
    
    private func setupTrackingUpdates() {
        // Cancel any existing task
        trackingMonitorTask?.cancel()
        
        // Create new task to monitor official tracking updates
        trackingMonitorTask = Task {
            for await trackingState in session.cameraTrackingUpdates {
                await MainActor.run {
                    print("Camera tracking updated to: \(trackingState)")
                    self.sessionTracking = trackingState
                    
                    // Show warning if tracking is lost
                    if case .notAvailable = trackingState {
                        self.showTrackingWarning = true
                    }
                }
            }
        }
    }
    
    // MARK: - Image Count Tracking
    
    private func updateCapturedImageCount() {
        guard let folderManager = appModel.scanFolderManager else { return }
        
        Task {
            do {
                let images = try FileManager.default.contentsOfDirectory(
                    at: folderManager.imagesFolder,
                    includingPropertiesForKeys: nil
                ).filter {
                    $0.pathExtension.lowercased() == "heic" ||
                    $0.pathExtension.lowercased() == "jpg" ||
                    $0.pathExtension.lowercased() == "jpeg"
                }
                
                await MainActor.run {
                    capturedImageCount = images.count
                }
            } catch {
                print("Error counting images: \(error)")
            }
        }
    }
    
    private func startImageCountTimer() {
        stopImageCountTimer()
        
        imageCountTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard self.isCapturing else {
                timer.invalidate()
                return
            }
            self.updateCapturedImageCount()
        }
        
        updateCapturedImageCount()
    }
    
    private func stopImageCountTimer() {
        imageCountTimer?.invalidate()
        imageCountTimer = nil
    }
    
    // MARK: - Helper Methods
    private func validateAndSetupSession() {
        isSessionReady = false
        isCameraReady = false
        isInitializing = true
        
        Task {
            // Add a timeout to prevent indefinite waiting
            let timeout = Task {
                try await Task.sleep(for: .seconds(1.8))
                await MainActor.run {
                    if !isSessionReady {
                        print("Session readiness timeout - forcing readiness")
                        isSessionReady = true
                        isCameraReady = true
                        isInitializing = false
                    }
                }
            }
            
            // Monitor session state changes
            let stateUpdates = session.stateUpdates
            
            for await state in stateUpdates {
                await MainActor.run {
                    print("Session state updated to: \(state)")
                    
                    switch state {
                    case .ready, .detecting, .capturing:
                        isSessionReady = true
                        isCameraReady = true
                        isInitializing = false
                        timeout.cancel()
                        
                    case .failed(let error):
                        print("Session failed: \(error)")
                        initializationError = error
                        isSessionReady = true
                        isInitializing = false
                        timeout.cancel()
                        
                    default:
                        break
                    }
                }
            }
        }
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Use both tracking systems for now (official and custom) for compatibility
        setupTrackingUpdates()
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
                    _ = self.checkARTrackingStatus()
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
    }
    
    private func checkARTrackingStatus() -> Bool {
        if session.state == .ready || session.state == .detecting {
            print("Session appears to be in a ready state")
            self.isCameraReady = true
            self.isInitializing = false
            return true
        }
        return false
    }
    
    private func cleanupSession() {
        UIApplication.shared.isIdleTimerDisabled = false
        trackingMonitor.stopMonitoring()
        trackingMonitorTask?.cancel()
        trackingMonitorTask = nil
        stopImageCountTimer()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func startCapture() {
        guard isCameraReady else { return }
        
        print("Session state before starting capture: \(session.state)")
        
        guard session.state == .ready || session.state == .detecting else {
            let message = "Waiting for camera to initialize. Please try again in a moment."
            appModel.messageList.add(message)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                appModel.messageList.remove(message)
            }
            return
        }
        
        withAnimation(.easeInOut(duration: 0.5)) {
            isCapturing = true
        }
        
        session.startCapturing()
        capturedImageCount = 0
        startImageCountTimer()
    }
}

extension Notification.Name {
    static let ARSessionTrackingStateChanged = Notification.Name("ARSessionTrackingStateChanged")
    static let ARSessionDidBecomeActive = Notification.Name("ARSessionDidBecomeActive")
}
