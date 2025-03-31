//
//  JoinView.swift
//  CameraStreamer
//
//  Created by Ashley Davison on 28/03/2025.
//

import SwiftUI
import WebRTC
import MultipeerConnectivity

struct JoinView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = JoinViewModel()
    
    // Add onClose callback to communicate back to parent view
    var onClose: () -> Void
    
    // Add state to handle manual dismissal
    @State private var isBeingDismissed = false
    
    // Transformation states
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnification: CGFloat = 1.0
    
    @State private var rotation: Angle = .zero
    @GestureState private var rotationAngle: Angle = .zero
    
    @State private var position: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero
    
    // Gesture definitions remain the same...
    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($magnification) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                scale *= value
            }
    }
    
    var rotationGesture: some Gesture {
        RotationGesture()
            .updating($rotationAngle) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                rotation += value
            }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { currentState, gestureState, _ in
                gestureState = currentState.translation
            }
            .onEnded { value in
                position.width += value.translation.width
                position.height += value.translation.height
            }
    }
    
    // Combined gesture for multi-touch interaction
    var combinedGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(magnificationGesture, rotationGesture),
            dragGesture
        )
    }
    
    // Reset transformations
    func resetTransformations() {
        withAnimation(.spring()) {
            scale = 1.0
            rotation = .zero
            position = .zero
        }
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            // WebRTC video view with transformations
            WebRTCVideoView(videoView: viewModel.videoView)
                .ignoresSafeArea()
                .scaleEffect(scale * magnification)
                .rotationEffect(rotation + rotationAngle)
                .offset(x: position.width + dragOffset.width, y: position.height + dragOffset.height)
                .gesture(combinedGesture)
            
            VStack {
                // Status label
                Text(viewModel.statusMessage)
                    .font(.system(size: 18, weight: .medium))
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.top, 20)
                
                Spacer()
                
                // WebRTC Stats View - Always show if connected, regardless of history
                if viewModel.isConnected {
                    WebRTCStatsView(statsModel: viewModel.statsModel)
                        .id("stats-view") // Add id to force view to stay
                }
                
                HStack {
                    // Reset button
                    Button(action: resetTransformations) {
                        Text("Reset View")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(height: 40)
                            .padding(.horizontal, 12)
                            .background(Color.blue.opacity(0.7))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    // Close button
                    Button(action: {
                        // Mark that we're deliberately closing the view
                        isBeingDismissed = true
                        
                        // Clean up resources
                        viewModel.stopBrowsing()
                        viewModel.cleanup()
                        
                        // Call the onClose callback to notify parent view
                        onClose()
                        
                        // Dismiss this view
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Close")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 40)
                            .background(Color.red.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            // Initialize our WebRTC components on appearance
            viewModel.setupWebRTC()
            viewModel.setupMultipeerConnectivity()
        }
        .onDisappear {
            // Only clean up if this is a deliberate dismissal
            if isBeingDismissed {
                viewModel.stopBrowsing()
                viewModel.cleanup()
            } else {
                // If we're being dismissed for other reasons, try to prevent cleanup
                // This helps with state transitions during app model changes
                print("JoinView dismissed without explicit close - preventing cleanup")
            }
        }
        // Override the automatic dismissal if needed
        .interactiveDismissDisabled()
    }
}

// UIViewRepresentable for RTCMTLVideoView
struct WebRTCVideoView: UIViewRepresentable {
    let videoView: RTCMTLVideoView
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        // Configure for high-quality rendering
        videoView.videoContentMode = .scaleAspectFit
        
        // Enable high-performance rendering for 4K
        if let layer = videoView.layer as? CAMetalLayer {
            layer.framebufferOnly = false
            layer.allowsNextDrawableTimeout = false
        }
        
        return videoView
    }
    
    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // Nothing to update
    }
}

class JoinViewModel: NSObject, ObservableObject {
    @Published var statusMessage = "Searching for hosts..."
    @Published var isConnected = false
    
    var session: MCSession?
    var peerID: MCPeerID?
    var browser: MCNearbyServiceBrowser?
    
    var peerConnection: RTCPeerConnection?
    var factory: RTCPeerConnectionFactory?
    var remoteVideoTrack: RTCVideoTrack?
    var dataChannel: RTCDataChannel?
    
    // Stats collection
    let videoView = RTCMTLVideoView(frame: .zero)
    lazy var statsModel = WebRTCStatsModel(peerConnection: peerConnection)
    
    func setupMultipeerConnectivity() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID!, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: peerID!, serviceType: "webrtc-stream")
        browser?.delegate = self
        startBrowsing()
    }
    
    func setupWebRTC() {
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        videoEncoderFactory.preferredCodec = RTCVideoCodecInfo(name: "H264")
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

        factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)

        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        
        // Create media constraints that explicitly disable audio
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "false"
        ], optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
                
        peerConnection = factory?.peerConnection(with: config, constraints: constraints, delegate: self)
        
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = false
        dataChannelConfig.maxRetransmits = 0
        dataChannel = peerConnection?.dataChannel(forLabel: "data", configuration: dataChannelConfig)
        
        // Initialize stats model with the peer connection
        statsModel = WebRTCStatsModel(peerConnection: peerConnection)
    }
    
    func handleRemoteSessionDescription(_ description: RTCSessionDescription) {
        peerConnection?.setRemoteDescription(description) { [weak self] error in
            if let error = error {
                print("Failed to set remote description: \(error)")
                return
            }
            
            if description.type == .offer {
                self?.createAnswer()
            }
        }
    }
    
    func createAnswer() {
        // Explicitly disable audio in the answer
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "false",
            "OfferToReceiveVideo": "true"
        ], optionalConstraints: [
            "VoiceActivityDetection": "false"
        ])
        
        peerConnection?.answer(for: constraints) { [weak self] (sdp, error) in
            guard let sdp = sdp, error == nil else {
                print("Failed to create answer: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            self?.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    print("Failed to set local description: \(error.localizedDescription)")
                    return
                }
                
                guard let sessionDescription = self?.peerConnection?.localDescription else { return }
                self?.sendSessionDescription(sessionDescription)
            }
        }
    }
    
    func sendSessionDescription(_ description: RTCSessionDescription) {
        do {
            let data = try JSONEncoder().encode(WebRTCSessionDescription(from: description))
            try session?.send(data, toPeers: session?.connectedPeers ?? [], with: .reliable)
        } catch {
            print("Failed to send session description: \(error)")
        }
    }
    
    func sendIceCandidate(_ candidate: RTCIceCandidate) {
        do {
            let data = try JSONEncoder().encode(WebRTCIceCandidate(from: candidate))
            try session?.send(data, toPeers: session?.connectedPeers ?? [], with: .reliable)
        } catch {
            print("Failed to send ICE candidate: \(error)")
        }
    }
    
    func startBrowsing() {
        browser?.startBrowsingForPeers()
    }
    
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
    }
    
    func cleanup() {
        statsModel.stopStatsCollection()
        peerConnection?.close()
    }
}

extension JoinViewModel: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let info = info, info["type"] == "host" else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "Found host: \(peerID.displayName). Connecting..."
        }
        
        browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 30)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error)")
    }
}

extension JoinViewModel: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.statusMessage = "Connected to \(peerID.displayName)"
            case .connecting:
                self?.statusMessage = "Connecting to \(peerID.displayName)..."
            case .notConnected:
                self?.statusMessage = "Disconnected from \(peerID.displayName)"
                self?.isConnected = false
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            if let iceCandidate = try? JSONDecoder().decode(WebRTCIceCandidate.self, from: data) {
                let candidate = iceCandidate.rtcIceCandidate
                // Use the updated method with completionHandler
                peerConnection?.add(candidate) { error in
                    if let error = error {
                        print("Failed to add ICE candidate: \(error)")
                    }
                }
            } else if let remoteDescription = try? JSONDecoder().decode(WebRTCSessionDescription.self, from: data) {
                let description = remoteDescription.rtcSessionDescription
                handleRemoteSessionDescription(description)
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension JoinViewModel: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state changed: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch newState {
            case .connected:
                self.statusMessage = "ICE Connected"
                self.isConnected = true
                
                // Keep isConnected true and ensure stats collection continues
                // Start stats collection once connected
                self.statsModel.setupStatsCollection()
                
            case .disconnected:
                self.statusMessage = "ICE Disconnected"
                // Don't set isConnected to false here to avoid UI flickering
                // self.isConnected = false
                
            case .failed:
                self.statusMessage = "ICE Connection Failed"
                self.isConnected = false
                
            default:
                break
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        sendIceCandidate(candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let videoTrack = rtpReceiver.track as? RTCVideoTrack {
            remoteVideoTrack = videoTrack
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.remoteVideoTrack?.add(self.videoView)
            }
        }
    }
}
