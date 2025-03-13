//
//  StreamingView.swift
//  Surface Capture
//

import SwiftUI
import MultipeerConnectivity

struct StreamingView: View {
    @ObservedObject var streamingService: ARStreamingService
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showingModeToggle = true
    @State private var streamActive = false
    
    var body: some View {
        VStack {
            // Header with title and close button
            HStack {
                Spacer()
                
                Text("AR Streaming")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    // Stop streaming before dismissing
                    if streamActive {
                        streamingService.stopStreaming()
                        streamActive = false
                    }
                    
                    // Disconnect if needed
                    if streamingService.isConnected {
                        streamingService.disconnect()
                    }
                    
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
            }
            .padding()
            
            // Main content
            VStack(spacing: 25) {
                if showingModeToggle && !streamingService.isConnected {
                    // Mode selection
                    ModeSelectionView(streamingService: streamingService)
                        .transition(.opacity)
                }
                
                // Connection status
                ConnectionStatusView(streamingService: streamingService)
                
                // Connected peers
                if streamingService.isConnected {
                    ConnectedPeersView(peers: streamingService.peers)
                    
                    // Streaming controls (only visible when connected)
                    StreamingControlView(
                        streamActive: $streamActive,
                        onStartStreaming: {
                            streamActive = true
                        },
                        onStopStreaming: {
                            streamingService.stopStreaming()
                            streamActive = false
                        }
                    )
                }
                
                // Error message (if any)
                if let errorMessage = streamingService.errorMessage {
                    ErrorMessageView(message: errorMessage)
                }
                
                Spacer()
            }
            .padding()
            .animation(.easeInOut, value: streamingService.isConnected)
            .animation(.easeInOut, value: streamingService.sessionState)
            .animation(.easeInOut, value: streamingService.errorMessage != nil)
        }
        .background(Color(.systemBackground).opacity(0.95))
        .onAppear {
            // Auto-start hosting when view appears
            if streamingService.sessionState == .idle {
                streamingService.startHosting()
            }
        }
        .onDisappear {
            // Clean up if the user dismisses without using the close button
            if streamActive {
                streamingService.stopStreaming()
            }
        }
    }
}

// MARK: - Subviews

struct ModeSelectionView: View {
    @ObservedObject var streamingService: ARStreamingService
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Connection Mode")
                .font(.headline)
            
            HStack(spacing: 20) {
                // Host mode button
                Button(action: {
                    streamingService.startHosting()
                }) {
                    VStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 24))
                            .foregroundColor(streamingService.isHosting ? .blue : .gray)
                        
                        Text("Host")
                            .font(.subheadline)
                    }
                    .frame(width: 100, height: 80)
                    .background(streamingService.isHosting ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                .disabled(streamingService.isJoining)
                
                // Join mode button
                Button(action: {
                    streamingService.startJoining()
                }) {
                    VStack {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 24))
                            .foregroundColor(streamingService.isJoining ? .blue : .gray)
                        
                        Text("Join")
                            .font(.subheadline)
                    }
                    .frame(width: 100, height: 80)
                    .background(streamingService.isJoining ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                .disabled(streamingService.isHosting)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(15)
    }
}

struct ConnectionStatusView: View {
    @ObservedObject var streamingService: ARStreamingService
    
    var statusColor: Color {
        switch streamingService.sessionState {
        case .connected:
            return .green
        case .hosting, .joining, .starting:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .gray
        }
    }
    
    var statusText: String {
        switch streamingService.sessionState {
        case .connected:
            return "Connected"
        case .hosting:
            return "Hosting - Waiting for connections..."
        case .joining:
            return "Searching for hosts..."
        case .starting:
            return "Starting..."
        case .failed:
            return "Connection failed"
        case .idle:
            return "Idle"
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            // Status text
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Disconnect button (only shown when connected)
            if streamingService.isConnected {
                Button(action: {
                    streamingService.disconnect()
                }) {
                    Text("Disconnect")
                        .font(.footnote)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 15)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

struct ConnectedPeersView: View {
    let peers: [MCPeerID]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            Text("Connected Devices (\(peers.count))")
                .font(.headline)
                .foregroundColor(.primary)
            
            // List of peers
            if peers.isEmpty {
                Text("No connected devices")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 5)
            } else {
                ForEach(peers, id: \.displayName) { peer in
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(.blue)
                        
                        Text(peer.displayName)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

struct StreamingControlView: View {
    @Binding var streamActive: Bool
    let onStartStreaming: () -> Void
    let onStopStreaming: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Streaming Controls")
                .font(.headline)
            
            // Toggle button
            Button(action: {
                if streamActive {
                    onStopStreaming()
                } else {
                    onStartStreaming()
                }
            }) {
                HStack {
                    Image(systemName: streamActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                    
                    Text(streamActive ? "Stop Streaming" : "Start Streaming")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(streamActive ? Color.red.opacity(0.7) : Color.green.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            // Status text
            Text(streamActive ? "Streaming is active" : "Ready to stream")
                .font(.subheadline)
                .foregroundColor(streamActive ? .green : .gray)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(10)
    }
}

struct ErrorMessageView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(.white)
            .padding()
            .background(Color.red.opacity(0.8))
            .cornerRadius(10)
            .multilineTextAlignment(.center)
    }
}

#if DEBUG
struct StreamingView_Previews: PreviewProvider {
    static var previews: some View {
        let service = ARStreamingService()
        // Simulate different states for preview
        service.isHosting = true
        service.sessionState = .hosting
        
        return StreamingView(streamingService: service)
            .preferredColorScheme(.dark)
    }
}
#endif
