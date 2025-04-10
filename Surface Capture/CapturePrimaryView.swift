//
//  CapturePrimaryView.swift
//  Surface Capture App
//

import SwiftUI
import RealityKit
import ARKit
import os
import Combine
import AVFoundation
import MediaPlayer

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
    @State private var isManualCapturing = false
    
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
    
    // Scene Mesh Visualization
    @State private var showSceneMesh: Bool = true
    @State private var sceneMeshWireframe: Bool = true
    @State private var sceneMeshRainbow: Bool = false
    @State private var sceneMeshOpacity: Float = 0.7
    
    // Legacy tracking monitor - kept for backward compatibility
    private let trackingMonitor = EnhancedTrackingMonitor()
    
    @State private var originalAudioCategory: AVAudioSession.Category?
    @State private var originalAudioMode: AVAudioSession.Mode?
    @State private var originalAudioOptions: AVAudioSession.CategoryOptions?
    
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
                //CustomObjectCaptureView(session: session)
                    .edgesIgnoringSafeArea(.all)
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
                    VStack(spacing: 15) {
                        // Add manual capture button
                        Button(
                            action: {
                                session.requestImageCapture()
                            },
                            label: {
                                ZStack {
                                    // Inner circle with camera button
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 45, height: 45)
                                    
                                    // Outer circle stroke
                                    Circle()
                                        .stroke(Color.white.opacity(1), lineWidth: 2)
                                        .frame(width: 50, height: 50)
                                }
                                .scaleEffect(isManualCapturing ? 0.9 : 1.0)
                                .animation(.spring(response: 0.2), value: isManualCapturing)
                            }
                        )
                        .disabled(!session.canRequestImageCapture)
                        .opacity(session.canRequestImageCapture ? 1.0 : 0.5)

                    // Progress button
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
                }
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
        
        // Start joining WebRTC stream
        private func startJoiningStream() {
            // Gracefully end the object capture session without triggering errors
            appModel.endObjectCaptureSession()
            // Show the streaming view
            showStreamingView = true
        }
        
        var body: some View {
            Button(action: {
                startJoiningStream()
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
            }) {
                // Present the JoinView as a full-screen cover
                JoinView(onClose: {
                    // This handles when the user explicitly closes the JoinView
                    showStreamingView = false
                })
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
    /*
    private func muteSystemVolume() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Store original settings
            originalAudioCategory = audioSession.category
            originalAudioMode = audioSession.mode
            originalAudioOptions = audioSession.categoryOptions
            
            // Set to a silent mode - this should minimize system sounds
            try audioSession.setCategory(.ambient, mode: .default, options: [])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Additional step to minimize sounds
            // We can't directly set volume, but we can deactivate and reactivate
            try audioSession.setActive(false)
            try audioSession.setActive(true)
        } catch {
            print("Failed to silence audio: \(error)")
        }
    }
    
    private func restoreSystemVolume() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            if let originalCategory = originalAudioCategory,
               let originalMode = originalAudioMode {
                try audioSession.setCategory(originalCategory,
                                            mode: originalMode,
                                            options: originalAudioOptions ?? [])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            }
        } catch {
            print("Failed to restore audio: \(error)")
        }
    }
    */
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
                    case .ready, .detecting:
                        isSessionReady = true
                        isCameraReady = true  // Only enable camera when truly ready
                        isInitializing = false
                        timeout.cancel()
                        
                    case .failed(let error):
                        print("Session failed: \(error)")
                        initializationError = error
                        isSessionReady = true
                        isInitializing = false
                        timeout.cancel()
                        
                    default:
                        // Don't mark camera as ready for other states
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
        //restoreSystemVolume()
    }
    
    private func startCapture() {
        guard isCameraReady else { return }
        
        print("Session state before starting capture: \(session.state)")
        
        // Only start capturing if the session is in the ready or detecting state
        guard session.state == .ready || session.state == .detecting else {
            let message = "Waiting for camera to initialize. Please try again in a moment."
            appModel.messageList.add(message)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                appModel.messageList.remove(message)
            }
                        
            return
        }

        //muteSystemVolume()
        
        //withAnimation(.easeInOut(duration: 0.5)) {
            isCapturing = true
        //}
        
        session.startCapturing()
        capturedImageCount = 0
        startImageCountTimer()
    }
}

extension Notification.Name {
    static let ARSessionTrackingStateChanged = Notification.Name("ARSessionTrackingStateChanged")
    static let ARSessionDidBecomeActive = Notification.Name("ARSessionDidBecomeActive")
}

/*
struct CustomObjectCaptureView: UIViewRepresentable {
    var session: ObjectCaptureSession
    
    // Reference to store our task and timer
    class Coordinator: NSObject {
        var trackingTask: Task<Void, Never>?
        var removalTimer: Timer?
        var stateMonitorTask: Task<Void, Never>?
        var trackingChangeMonitor: Task<Void, Never>?
        var focusNodeObserver: NSKeyValueObservation?
        var isCapturing: Bool = false
        var hostingController: UIHostingController<ObjectCaptureView<EmptyView>>?
        
        // Keep track of whether we've already created a focus entity
        var focusEntityCreated: Bool = false
        var focusEntityManager: FocusEntityManager?
        
        deinit {
            print("CustomObjectCaptureView coordinator deinit")
            trackingTask?.cancel()
            removalTimer?.invalidate()
            stateMonitorTask?.cancel()
            trackingChangeMonitor?.cancel()
            focusNodeObserver?.invalidate()
            focusEntityManager?.cleanup()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        // Create a container view
        let containerView = UIView(frame: .zero)
        containerView.tag = 9876 // Unique tag to identify this container
        
        // Create the ObjectCaptureView - explicitly hide object reticle
        let objectCaptureView = ObjectCaptureView(session: session)
            .hideObjectReticle(true) // Use the official API
        
        // Add ObjectCaptureView to container
        let hostingController = UIHostingController(rootView: objectCaptureView)
        context.coordinator.hostingController = hostingController
        
        // Add as child view controller to handle lifecycle correctly
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let parentVC = window.rootViewController {
            
            parentVC.addChild(hostingController)
            containerView.addSubview(hostingController.view)
            hostingController.view.frame = containerView.bounds
            hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            hostingController.didMove(toParent: parentVC)
                        
            // Initial removal of UI elements - always do this regardless of capturing state
            removeARFocusElements(in: hostingController.view)
            removeExcessFocusEntities(in: hostingController.view, preserveMain: true)
            
            // DON'T call findARViewAndSetupFocusEntity here anymore
            // We'll do it when we detect capturing state
            
            // Set up a recurrent timer to periodically check and clean up
            context.coordinator.removalTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak hostingController] _ in
                guard let view = hostingController?.view else { return }
                
                // Always remove unwanted UI elements
                removeARFocusElements(in: view)
                findAndHideSmallCircularElements(in: view, preserveCamera: true)
                removeExcessFocusEntities(in: view, preserveMain: true)
                
                // But only ensure the focus entity is visible if we're capturing
                if context.coordinator.isCapturing {
                    context.coordinator.focusEntityManager?.setVisible(true)
                } else {
                    context.coordinator.focusEntityManager?.setVisible(false)
                }
            }
            
            // Start tracking changes monitor
            context.coordinator.trackingChangeMonitor = Task {
                for await trackingState in session.cameraTrackingUpdates {
                    print("Camera tracking updated to: \(trackingState)")
                    
                    // When tracking becomes limited, aggressively remove coaching overlay
                    if case .limited = trackingState {
                        await MainActor.run {
                            print("Tracking became limited - removing coaching overlay")
                            // Schedule removals with delays
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                aggressivelyRemoveCoachingOverlay(in: hostingController.view)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                aggressivelyRemoveCoachingOverlay(in: hostingController.view)
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                aggressivelyRemoveCoachingOverlay(in: hostingController.view)
                            }
                        }
                    } else if case .normal = trackingState {
                        await MainActor.run {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                findAndHideSmallCircularElements(in: hostingController.view, preserveCamera: true)
                            }
                        }
                    }
                }
            }
            
            // Monitor session state to know when capturing begins/ends
            context.coordinator.stateMonitorTask = Task {
                for await state in session.stateUpdates {
                    await MainActor.run {
                        print("Session state updated to: \(state)")
                        
                        if case .capturing = state {
                            // We're now capturing - initialize the FocusEntity if needed and show it
                            context.coordinator.isCapturing = true
                            
                            if context.coordinator.focusEntityManager == nil {
                                // Only now do we initialize the FocusEntity
                                findARViewAndSetupFocusEntity(in: hostingController.view, coordinator: context.coordinator)
                            } else {
                                // Just make it visible if it already exists
                                context.coordinator.focusEntityManager?.setVisible(true)
                            }
                        } else {
                            // We're not capturing - hide the FocusEntity
                            context.coordinator.isCapturing = false
                            context.coordinator.focusEntityManager?.setVisible(false)
                        }
                        
                        // Always clean up unwanted elements
                        removeARFocusElements(in: hostingController.view)
                        removeExcessFocusEntities(in: hostingController.view, preserveMain: true)
                    }
                }
            }
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Make sure we preserve the camera view on updates
        if let hostView = context.coordinator.hostingController?.view {
            // Remove unwanted UI elements but preserve the camera view
            removeARFocusElements(in: hostView)
            findAndHideSmallCircularElements(in: hostView, preserveCamera: true)
            
            // Remove any excess focus entities but keep our main one
            removeExcessFocusEntities(in: hostView, preserveMain: true)
            
            // Ensure our focus entity is visible
            context.coordinator.focusEntityManager?.setVisible(true)
        }
    }
    
    // MARK: - Private Helper Methods
    
    // Special method to aggressively remove coaching overlay when tracking becomes limited
    private func aggressivelyRemoveCoachingOverlay(in view: UIView?) {
        guard let view = view else { return }
        
        // First check direct subviews
        for subview in view.subviews {
            // Look specifically for ARCoachingOverlayView
            if String(describing: type(of: subview)) == "ARCoachingOverlayView" {
                print("Found ARCoachingOverlayView during tracking limitation - removing")
                
                // Try multiple methods to disable it
                if let coachingOverlay = subview as? ARCoachingOverlayView {
                    coachingOverlay.setActive(false, animated: false)
                    coachingOverlay.delegate = nil
                    coachingOverlay.session = nil
                }
                
                // Also use Objective-C runtime to disable it
                let selector = NSSelectorFromString("setActive:animated:")
                if subview.responds(to: selector) {
                    subview.perform(selector, with: false, with: false)
                }
                
                // Hide and remove it
                subview.isHidden = true
                subview.removeFromSuperview()
            }
            
            // Recursively check subviews
            if !subview.subviews.isEmpty {
                aggressivelyRemoveCoachingOverlay(in: subview)
            }
        }
        
        // Also try to find the ARView and disable its coaching overlay
        for subview in view.subviews {
            if String(describing: type(of: subview)).contains("ARView") {
                if let arView = subview as? ARView {
                    // Try to find coaching overlay property through reflection
                    let mirror = Mirror(reflecting: arView)
                    for child in mirror.children {
                        if let label = child.label {
                            if label.contains("coach") || label.contains("overlay") {
                                if let overlayObject = child.value as AnyObject? {
                                    // Try to disable it
                                    overlayObject.setValue(false, forKey: "active")
                                    overlayObject.setValue(nil, forKey: "session")
                                    overlayObject.setValue(nil, forKey: "delegate")
                                }
                            }
                        }
                    }
                }
                
                // Continue checking subviews
                if !subview.subviews.isEmpty {
                    aggressivelyRemoveCoachingOverlay(in: subview)
                }
            }
        }
    }
    
    // TODO: Not sure if needed as isn't in subview
    private func isFocusEntity(_ view: UIView) -> Bool {
        // Check if this is our FocusEntity by looking at its class hierarchy
        let className = String(describing: type(of: view))
        print("!!!!! FocusEntity !!!!!!: \(className)")

        // FocusEntity related classes should be skipped
        return className.contains("FocusEntity") && !className.contains("ARKit") &&
               !className.contains("ReticleView") && !className.contains("ObjectReticle")
    }
    
    // Comprehensive removal of all AR focus-related elements
    private func removeARFocusElements(in view: UIView?) {
        guard let view = view else { return }
        
        // Remove coaching overlays
        for subview in view.subviews {
            // Check if it's an ARCoachingOverlayView
            if String(describing: type(of: subview)) == "ARCoachingOverlayView" {
                if let coachingOverlay = subview as? ARCoachingOverlayView {
                    coachingOverlay.setActive(false, animated: false)
                }
                subview.isHidden = true
                subview.removeFromSuperview()
                continue
            }
            
            // Skip if it's our own FocusEntity
            if isFocusEntity(subview) {
                print("Preserving our FocusEntity: \(String(describing: type(of: subview)))")
                continue
            }
            
            // Check if it's a camera view - NEVER HIDE THIS
            let className = String(describing: type(of: subview))
            if className.contains("Camera") || className.contains("SCNView") ||
               className.contains("MetalView") || (className.contains("AR") && subview.frame.size.width > 200) {
                
                // Camera views are large and fill most of the screen - don't hide them
                print("Preserving camera view: \(className)")
                
                // Continue with other subviews
                if !subview.subviews.isEmpty {
                    removeARFocusElements(in: subview)
                }
                continue
            }
            
            // Hide anything that might be a focus entity or reticle, but not our own FocusEntity
            if (className.contains("Reticle") || className.contains("reticle") ||
                className.contains("Indicator")) && !isFocusEntity(subview) {
                
                subview.isHidden = true
                print("Hidden potential AR element: \(className)")
            }
            
            // Recursively process subviews
            if !subview.subviews.isEmpty {
                removeARFocusElements(in: subview)
            }
        }
        
        // Try to access ARView and disable its focus entities
        findARViewsAndDisableFocusEntities(in: view)
    }
    
    // Modified to be careful with camera view
    private func findAndHideSmallCircularElements(in view: UIView, preserveCamera: Bool) {
        for subview in view.subviews {
            
            // Skip if it's our own FocusEntity
            if isFocusEntity(subview) {
                print("Preserving our FocusEntity in small circular check")
                continue
            }
            
            // Check for small circular elements - could be the dot
            if subview.layer.cornerRadius > 0 || subview.layer.masksToBounds {
                let size = subview.frame.size
                
                // If it's small and roughly circular
                if size.width < 30 && size.height < 30 && abs(size.width - size.height) < 5 {
                    subview.isHidden = true
                    print("Hidden small circular element")
                    continue
                }
            }
            // FIRST CHECK: Skip camera views
            let className = String(describing: type(of: subview))
            let isCameraView = className.contains("Camera") || className.contains("SCNView") ||
                              className.contains("MetalView") || className.contains("ARView") ||
                              (className.contains("AR") && subview.frame.size.width > 200)
            
            if preserveCamera && isCameraView {
                // Skip hiding this view - it's likely the camera view
                print("Preserving potential camera view: \(className)")
                
                // But still check its subviews for elements to hide
                if !subview.subviews.isEmpty {
                    findAndHideSmallCircularElements(in: subview, preserveCamera: preserveCamera)
                }
                continue
            }
            
            // Skip large views that take up most of the screen - these are likely important
            if subview.frame.width > UIScreen.main.bounds.width * 0.8 &&
               subview.frame.height > UIScreen.main.bounds.height * 0.8 {
                // This is likely a main content view - don't hide it
                if !subview.subviews.isEmpty {
                    findAndHideSmallCircularElements(in: subview, preserveCamera: preserveCamera)
                }
                continue
            }
            
            // Look for elements in the center of the screen
            let viewCenter = subview.center
            if let parentView = subview.superview {
                let parentCenter = CGPoint(x: parentView.bounds.midX, y: parentView.bounds.midY)
                let centerDistance = hypot(viewCenter.x - parentCenter.x, viewCenter.y - parentCenter.y)
                
                // If it's near the center and small, it's likely the focus dot
                if centerDistance < 100 && subview.bounds.width < 40 && subview.bounds.height < 40 {
                    subview.isHidden = true
                    print("Hidden small element near center")
                    continue
                }
            }
            
            // Look for any small UIImageView elements that might be showing a dot
            if subview is UIImageView || className.contains("ImageView") {
                let size = subview.frame.size
                if size.width < 30 && size.height < 30 {
                    subview.isHidden = true
                    print("Hidden small image view that might be a dot")
                    continue
                }
            }
            
            // Recursively process subviews
            if !subview.subviews.isEmpty {
                findAndHideSmallCircularElements(in: subview, preserveCamera: preserveCamera)
            }
        }
    }
    
    private func createFocusEntity(with arView: ARView, coordinator: Coordinator) {
        print("Creating FocusEntity on ARView")
        
        // Create the focus entity manager if it doesn't exist yet
        if coordinator.focusEntityManager == nil {
            // Create the focus entity manager
            let manager = FocusEntityManager(for: arView)
            
            // Store the manager in the coordinator
            coordinator.focusEntityManager = manager
            
            // Ensure the focus entity is visible
            manager.setVisible(true)
            
            print("FocusEntity successfully created")
        } else {
            print("FocusEntity already exists")
        }
    }

    private func findARViewByReflection(in view: UIView, coordinator: Coordinator) {
        // Function to check a view and its subviews for AR-related methods or properties
        func checkViewForARSession(_ view: UIView) -> UIView? {
            // Check if the view responds to AR-related selectors
            if view.responds(to: #selector(getter: ARView.session)) ||
               view.responds(to: Selector(("arSession"))) ||
                view.responds(to: #selector(setter: ARView.session)) {
                print("Found view responding to AR session selectors: \(String(describing: type(of: view)))")
                return view
            }
            
            // Check property list for properties containing "session"
            let mirror = Mirror(reflecting: view)
            for child in mirror.children {
                if let label = child.label,
                   (label.contains("session") || label.contains("Session")) {
                    print("Found view with AR session property: \(String(describing: type(of: view)))")
                    return view
                }
            }
            
            // Recursively check subviews
            for subview in view.subviews {
                if let arView = checkViewForARSession(subview) {
                    return arView
                }
            }
            
            return nil
        }
        
        // Try to find a view with AR session
        if let potentialARView = checkViewForARSession(view) {
            print("Last resort found potential ARView: \(String(describing: type(of: potentialARView)))")
            
            // Create focus entity on this view as a best effort
            if let arView = potentialARView as? ARView {
                createFocusEntity(with: arView, coordinator: coordinator)
            } else {
                print("Found view is not an ARView, cannot create focus entity")
                
                // Check if view contains an ARView
                for subview in potentialARView.subviews {
                    if let arView = subview as? ARView {
                        createFocusEntity(with: arView, coordinator: coordinator)
                        return
                    }
                }
            }
        } else {
            print("Failed to find any view with AR session capability")
        }
    }
    
    // New method to find ARView and setup FocusEntity
    private func findARViewAndSetupFocusEntity(in view: UIView, coordinator: Coordinator) {
        // Skip if we already have a FocusEntityManager
        guard coordinator.focusEntityManager == nil && !coordinator.focusEntityCreated else {
            print("FocusEntity already exists - skipping additional setup")
            return
        }
        
        // Function to perform ARView search with progressive delays
        func attemptARViewSearch(attempt: Int = 1, maxAttempts: Int = 5) {
            print("ARView search attempt \(attempt)/\(maxAttempts)")
            
            // Simple function to search for ARView (not recursive)
            func findARView(in view: UIView) -> ARView? {
                // Direct check if the view is an ARView
                if let arView = view as? ARView {
                    print("Direct ARView found in attempt \(attempt)")
                    return arView
                }
                
                // Check immediate children
                for subview in view.subviews {
                    if let arView = subview as? ARView {
                        print("ARView found in subview in attempt \(attempt)")
                        return arView
                    }
                    
                    // Check one level deeper for ARView
                    for deeperView in subview.subviews {
                        if let arView = deeperView as? ARView {
                            let deepClassName = String(describing: type(of: deeperView))
                            print("ARView found in deeper level in attempt \(attempt)")
                            print("ARView name: \(deepClassName)")
                            // TODO: Always seems to catch ARview here so can delete rest. Log: "ARView name: ARView"
                            // I think that ObjectCaptureView (which has subview of Arview we're piggy-backing off of, has different tracking state data prior and post capturing
                            // We do know only one Focus Entity is being addded to the right ARView now, but cannot determing why is acting differenting post and prior: white segmented, intense emissive glow prior, etc.
                            return arView
                        }
                        
                        // Look specifically for UIViews containing metal or SCN in their class name
                        // as these are likely to be ARViews or their containers
                        let deeperClassName = String(describing: type(of: deeperView))
                        if deeperClassName.contains("Metal") ||
                           deeperClassName.contains("SCN") ||
                           deeperClassName.contains("AR") {
                            print("Found potential AR container: \(deeperClassName)")
                            
                            // Look inside this potential container
                            for potentialARView in deeperView.subviews {
                                if let arView = potentialARView as? ARView {
                                    print("ARView found inside container in attempt \(attempt)")
                                    return arView
                                }
                            }
                        }
                    }
                }
                
                // Look for any view that seems like it might be AR-related
                func findPotentialARViews(in view: UIView) -> [UIView] {
                    var potentialViews: [UIView] = []
                    
                    let className = String(describing: type(of: view))
                    if className.contains("AR") ||
                       className.contains("Metal") ||
                       className.contains("SCN") {
                        potentialViews.append(view)
                    }
                    
                    for subview in view.subviews {
                        potentialViews.append(contentsOf: findPotentialARViews(in: subview))
                    }
                    
                    return potentialViews
                }
                
                // Find potential AR views and log them
                let potentialARViews = findPotentialARViews(in: view)
                if !potentialARViews.isEmpty {
                    print("Found \(potentialARViews.count) potential AR-related views:")
                    for (index, potentialView) in potentialARViews.enumerated() {
                        print("  \(index): \(String(describing: type(of: potentialView)))")
                    }
                }
                
                return nil
            }
            
            // First try to find ARView directly
            if let arView = findARView(in: view) {
                print("Successfully found ARView on attempt \(attempt)")
                createFocusEntity(with: arView, coordinator: coordinator)
                return
            }
            
            // If we didn't find it and haven't reached max attempts, try again with delay
            if attempt < maxAttempts {
                let delay = 0.2 * Double(attempt) // Increasing delay with each attempt
                print("ARView not found, retrying in \(delay) seconds...")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    attemptARViewSearch(attempt: attempt + 1, maxAttempts: maxAttempts)
                }
            } else {
                print("Failed to find ARView after \(maxAttempts) attempts")
                
                // Last resort: check if any view has a method or property related to AR session
                print("Attempting last resort search for ARView...")
                findARViewByReflection(in: view, coordinator: coordinator)
            }
        }
        
        // Mark that we're starting the search process
        coordinator.focusEntityCreated = true
        
        // Start the progressive search
        attemptARViewSearch()
    }
    
    // Method to properly identify and remove excess focus entities
    private func removeExcessFocusEntities(in view: UIView, preserveMain: Bool = true) {
        // Get references to all views that could be focus entities
        var potentialFocusEntities: [UIView] = []
        
        // Recursive function to find all potential focus entities
        func findPotentialFocusEntities(in view: UIView) {
            let className = String(describing: type(of: view))
            
            // Check if it might be a focus entity
            if className.contains("FocusEntity") ||
               (className.contains("Entity") && className.contains("Focus")) {
                potentialFocusEntities.append(view)
            }
            
            // Check all subviews
            for subview in view.subviews {
                findPotentialFocusEntities(in: subview)
            }
        }
        
        // Find all potential focus entities
        findPotentialFocusEntities(in: view)
        
        print("Found \(potentialFocusEntities.count) potential focus entities")
        
        // If we only want to preserve the main one and found multiple
        if preserveMain && potentialFocusEntities.count > 1 {
            // Skip the first one (assumed to be the main one) and remove the rest
            for i in 1..<potentialFocusEntities.count {
                potentialFocusEntities[i].isHidden = true
                potentialFocusEntities[i].removeFromSuperview()
            }
        }
    }
    
    // Find ARViews and disable their focus entities, but be careful not to disable the view itself
    private func findARViewsAndDisableFocusEntities(in view: UIView) {
        for subview in view.subviews {
            // Look for ARView classes
            let className = String(describing: type(of: subview))
            if className.contains("ARView") || className.contains("ARSCNView") ||
               className.contains("SceneView") {
                
                // DON'T HIDE THE VIEW ITSELF!
                // subview.isHidden = false;  // Ensure the view itself is visible
                
                // Try to access focus-related properties through reflection
                let mirror = Mirror(reflecting: subview)
                for child in mirror.children {
                    if let label = child.label {
                        if label.contains("focus") || label.contains("reticle") ||
                           label.contains("indicator") || label.contains("placement") {
                            // Try to disable this property if it's an object
                            if let entity = child.value as? Entity {
                                entity.isEnabled = false
                                print("Disabled AR entity: \(label)")
                            } else if let object = child.value as AnyObject? {
                                // Try setting common properties to disable visibility
                                for property in ["isEnabled", "isVisible", "isHidden", "opacity"] {
                                    if object.responds(to: Selector(property)) {
                                        if property.contains("hidden") {
                                            object.setValue(true, forKey: property)
                                        } else if property.contains("opacity") {
                                            object.setValue(0.0, forKey: property)
                                        } else {
                                            object.setValue(false, forKey: property)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // If this is an ARView, try directly accessing its scene
                if let arView = subview as? ARView {
                    arView.debugOptions = []
                    
                    // Try to disable focus square through various means
                    if let method = class_getInstanceMethod(type(of: arView), Selector(("setFocusSquare:"))) {
                        let imp = method_getImplementation(method)
                        let function = unsafeBitCast(imp, to: (@convention(c) (AnyObject, Selector, Bool) -> Void).self)
                        function(arView, Selector(("setFocusSquare:")), false)
                    }
                    
                    // Find focus entities in scene but don't disable normal entities
                    for anchor in arView.scene.anchors {
                        disableFocusEntitiesOnly(anchor)
                    }
                }
            }
            
            // Recursively process subviews
            if !subview.subviews.isEmpty {
                findARViewsAndDisableFocusEntities(in: subview)
            }
        }
    }
    
    // Modified to ONLY disable focus/dot related entities, not all entities
    private func disableFocusEntitiesOnly(_ entity: Entity) {
        let entityName = entity.name.lowercased()
        let entityType = String(describing: type(of: entity))
        
        // Check if this entity is related to focus/reticle functionality
        if entityName.contains("reticle") ||
           entityName.contains("dot") || entityName.contains("point") ||
           entityType.contains("Reticle") {
            entity.isEnabled = false
            print("Disabled focus entity: \(entity.name)")
        }
        
        // For ModelEntity, check size to find the dot
        if let modelEntity = entity as? ModelEntity {
            let scale = modelEntity.scale
            // Only disable if it's very small (likely a dot) - not regular models
            if scale.x < 30 && scale.y < 30 && scale.z < 30 {
                modelEntity.isEnabled = false
                print("Disabled small model entity")
            }
        }
        
        // Recursively process children
        for child in entity.children {
            disableFocusEntitiesOnly(child)
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        print("Cleaning up CustomObjectCaptureView resources")
        coordinator.trackingTask?.cancel()
        coordinator.stateMonitorTask?.cancel()
        coordinator.removalTimer?.invalidate()
        coordinator.trackingChangeMonitor?.cancel()
        coordinator.focusNodeObserver?.invalidate()
        coordinator.focusEntityManager?.cleanup()
        
        // Need to properly clean up the hosting controller
        if let hostingController = coordinator.hostingController {
            hostingController.willMove(toParent: nil)
            hostingController.view.removeFromSuperview()
            hostingController.removeFromParent()
        }
    }
}
*/
