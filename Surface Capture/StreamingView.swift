//
//  StreamingView.swift
//  Surface Capture
//

import SwiftUI
import WebRTC
import Combine

struct StreamingView: View {
    @ObservedObject var webRTCService: WebRTCService
    var onDismiss: () -> Void
    
    // Add state variables to track connection status
    @State private var showConnectionError: Bool = false
    @State private var connectionErrorMessage: String = ""
    @State private var hasReceivedVideoFrame: Bool = false
    @State private var connectionTimer: Timer? = nil
    
    var body: some View {
        ZStack {
            // Main content - StreamingViewController
            StreamingViewControllerRepresentable(
                webRTCService: webRTCService,
                onDisconnect: onDismiss
            )
            .edgesIgnoringSafeArea(.all)
            
            // Connection error overlay
            if showConnectionError {
                ConnectionErrorView(
                    message: connectionErrorMessage,
                    onRetry: {
                        // Attempt to reconnect
                        retryConnection()
                    },
                    onDismiss: {
                        onDismiss()
                    }
                )
                .transition(.opacity)
                .animation(.easeInOut, value: showConnectionError)
            }
        }
        .onAppear {
            // Ensure we're using camera resources exclusively for streaming
            freezeARResourcesForStreaming()
            
            // Start monitoring connection
            startConnectionMonitoring()
        }
        .onDisappear {
            // Clean up resources and restore AR capabilities
            restoreARResources()
            
            // Clean up timers
            connectionTimer?.invalidate()
            connectionTimer = nil
        }
        .alert(isPresented: $showConnectionError) {
            Alert(
                title: Text("Connection Issue"),
                message: Text(connectionErrorMessage),
                primaryButton: .default(Text("Retry")) {
                    retryConnection()
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    onDismiss()
                }
            )
        }
    }
    
    // Start a timer to monitor connection status
    private func startConnectionMonitoring() {
        // Cancel any existing timer
        connectionTimer?.invalidate()
        
        // Create a new timer
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            checkConnectionStatus()
        }
    }
    
    // Check connection status
    private func checkConnectionStatus() {
        // If we're connected but haven't received a video frame after 10 seconds
        if webRTCService.isConnected && !hasReceivedVideoFrame {
            let timeSinceConnect = Date().timeIntervalSince(Date())
            
            if timeSinceConnect > 10.0 {
                // Show connection error
                connectionErrorMessage = "Connected but no video is being received. This may be due to network issues or camera permissions."
                showConnectionError = true
            }
        }
        
        // If we're not connected after 15 seconds
        if !webRTCService.isConnected && webRTCService.streamingState != .idle {
            let timeSinceStarted = Date().timeIntervalSince(Date())
            
            if timeSinceStarted > 15.0 {
                // Show connection error
                connectionErrorMessage = "Failed to establish a connection. Please check that both devices are on the same network."
                showConnectionError = true
            }
        }
        
        // Check for explicit error messages from the service
        if let error = webRTCService.errorMessage {
            connectionErrorMessage = error
            showConnectionError = true
            
            // Clear the error in the service
            webRTCService.errorMessage = nil
        }
        
        // Use the service's getStats method to check if frames are being received
        webRTCService.getStats { stats in
            var hasFrames = false
            
            stats.statistics.forEach { (statsId, statsObj) in
                if statsObj.type == "inbound-rtp" && statsObj.values["mediaType"] as? String == "video" {
                    if let framesDecoded = statsObj.values["framesDecoded"] as? Int32, framesDecoded > 0 {
                        hasFrames = true
                    }
                }
            }
            
            // Update state on main thread
            DispatchQueue.main.async {
                if hasFrames && !hasReceivedVideoFrame {
                    hasReceivedVideoFrame = true
                    showConnectionError = false
                }
            }
        }
    }
    
    // Retry the connection
    private func retryConnection() {
        // Disconnect current session
        webRTCService.disconnect()
        
        // Reset state
        hasReceivedVideoFrame = false
        showConnectionError = false
        
        // Wait a moment then reconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if webRTCService.isHosting {
                webRTCService.startHosting(withDirectCameraAccess: true)
            } else if webRTCService.isJoining {
                webRTCService.startJoining()
            }
        }
    }
    
    private func freezeARResourcesForStreaming() {
        // Ensure AR resources are released for WebRTC to work optimally
        
        // Request high priority for media capture
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }

    private func restoreARResources() {
        // Reset audio session to allow AR to function properly again
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
}

// Connection error view
struct ConnectionErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Connection Issue")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(message)
                .font(.body)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 20) {
                Button(action: onRetry) {
                    Text("Retry")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                Button(action: onDismiss) {
                    Text("Cancel")
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.gray)
                        .cornerRadius(8)
                }
            }
        }
        .padding(30)
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

// A custom representable to use StreamingViewController that's compatible with the existing implementation
struct StreamingViewControllerRepresentable: UIViewControllerRepresentable {
    var webRTCService: WebRTCService
    var onDisconnect: () -> Void
    
    func makeUIViewController(context: Context) -> StreamingViewController {
        let controller = StreamingViewController(webRTCService: webRTCService, onDisconnect: onDisconnect)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: StreamingViewController, context: Context) {
        // No updates needed
    }
}

// Lightweight version for hosting statistics and controls
struct StreamingHostOverlay: View {
    
    @State private var showStats = false
    @State private var connectionStats = "No statistics available"
    @State private var statsTimer: Timer? = nil
    
    @ObservedObject var webRTCService: WebRTCService
    var onToggleStreaming: () -> Void
    var statusMessage: String = ""
    
    var body: some View {
        ZStack {
            // Dark semi-transparent background to cover AR view
            // since we've paused it for camera access
            Color.black.opacity(0.9)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Text("Camera Streaming")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.top, 40)
                
                // Streaming status indicator
                HStack(spacing: 10) {
                    // Status indicator light
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    
                    // Status text
                    Text(statusMessage.isEmpty ? statusText : statusMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(15)
                .padding(.top, 20)
                
                Spacer()
                
                // Stats/info button
                Button(action: { showStats.toggle() }) {
                    HStack {
                        Image(systemName: showStats ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 20))
                        Text(showStats ? "Hide Stats" : "Show Stats")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(10)
                }
                
                // Connection stats
                if showStats {
                    ScrollView {
                        Text(connectionStats)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                    }
                    .padding()
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut, value: showStats)
                }
                
                // Connection info
                Text("Connected peers: \(webRTCService.connectedPeersCount)")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.bottom, 20)
                
                // Stop streaming button
                Button(action: {
                    onToggleStreaming()
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                        Text("Stop Streaming")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(10)
                }
                .padding(.bottom, 40)
                
                Text("AR session is paused while streaming")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            startStatsTimer()
        }
        .onDisappear {
            statsTimer?.invalidate()
        }
    }
    
    // Status color based on connection state
    private var statusColor: Color {
        switch webRTCService.streamingState {
        case .connected: return .green
        case .hosting, .joining, .starting: return .yellow
        case .failed: return .red
        case .idle: return .gray
        }
    }
    
    // Status text based on connection state
    private var statusText: String {
        switch webRTCService.streamingState {
        case .connected: return "Streaming Active"
        case .hosting: return "Waiting for connection..."
        case .starting: return "Starting stream..."
        case .joining: return "Connecting..."
        case .failed: return "Connection failed"
        case .idle: return "Stream inactive"
        }
    }
    
    // Start stats timer
    private func startStatsTimer() {
        statsTimer?.invalidate()
        
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            updateStats()
        }
        
        // Initial stats update
        updateStats()
    }
    
    // Update connection statistics
    private func updateStats() {
        guard webRTCService.isConnected else {
            connectionStats = "No active connection"
            return
        }
        
        webRTCService.getStats { stats in
            var statsText = ""
            
            // Access the statistics dictionary
            stats.statistics.forEach { (statsId, statsObject) in
                // Check for outbound-rtp stats for video (sending)
                if statsObject.type == "outbound-rtp" {
                    // For video stats
                    if statsObject.values["mediaType"] as? String == "video" {
                        statsText += "--- VIDEO OUTBOUND ---\n"
                        
                        if let bytesSent = statsObject.values["bytesSent"] as? Int64 {
                            statsText += "Sent: \(formatBytes(String(bytesSent)))\n"
                        }
                        
                        if let packetsSent = statsObject.values["packetsSent"] as? Int32 {
                            statsText += "Packets Sent: \(packetsSent)\n"
                        }
                        
                        if let frameWidth = statsObject.values["frameWidth"] as? Int32,
                           let frameHeight = statsObject.values["frameHeight"] as? Int32 {
                            statsText += "Resolution: \(frameWidth)×\(frameHeight)\n"
                        }
                        
                        if let framesPerSecond = statsObject.values["framesPerSecond"] as? Double {
                            statsText += "FPS: \(Int(framesPerSecond))\n"
                        }
                        
                        if let framesEncoded = statsObject.values["framesEncoded"] as? Int32 {
                            statsText += "Frames Encoded: \(framesEncoded)\n"
                        }
                        
                        statsText += "\n"
                    }
                }
                // Check for candidate-pair stats (connection quality)
                else if statsObject.type == "candidate-pair" && statsObject.values["nominated"] as? Bool == true {
                    statsText += "--- CONNECTION ---\n"
                    
                    // Get RTT from active candidate pair
                    if let rtt = statsObject.values["currentRoundTripTime"] as? Double {
                        let rttMs = Int(rtt * 1000)
                        statsText += "RTT: \(rttMs)ms\n"
                    }
                    
                    if let bytesSent = statsObject.values["bytesSent"] as? Int64 {
                        statsText += "Total Bytes Sent: \(formatBytes(String(bytesSent)))\n"
                    }
                    
                    if let bytesReceived = statsObject.values["bytesReceived"] as? Int64 {
                        statsText += "Total Bytes Received: \(formatBytes(String(bytesReceived)))\n"
                    }
                    
                    statsText += "\n"
                }
                // Check for codec info
                else if statsObject.type == "codec" {
                    if let mimeType = statsObject.values["mimeType"] as? String, mimeType.contains("video") {
                        statsText += "Codec: \(mimeType.split(separator: "/").last ?? "")\n"
                    }
                }
            }
            
            // Update stats text on main thread
            DispatchQueue.main.async {
                connectionStats = statsText.isEmpty ? "No statistics available" : statsText
            }
        }
    }
    
    // Format bytes to human-readable format
    private func formatBytes(_ bytesString: String) -> String {
        guard let bytes = Double(bytesString) else { return bytesString }
        
        let units = ["B", "KB", "MB", "GB"]
        var value = bytes
        var unitIndex = 0
        
        while value > 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
