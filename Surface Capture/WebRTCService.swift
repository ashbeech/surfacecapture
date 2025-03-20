//
//  WebRTCService.swift
//  Surface Capture
//

import Foundation
import AVFoundation
import MultipeerConnectivity
import WebRTC

// A service that manages WebRTC connections and streaming
class WebRTCService: NSObject, ObservableObject {
    // Published properties for UI updates
    @Published var isHosting = false
    @Published var isJoining = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var streamingState: StreamingState = .idle
    @Published var availablePeers: [MCPeerID] = []
    
    // Connection state
    enum StreamingState: String {
        case idle = "Idle"
        case starting = "Starting"
        case hosting = "Hosting"
        case joining = "Joining"
        case connected = "Connected"
        case failed = "Failed"
    }
    
    // Callbacks
    var onRemoteVideoTrackReceived: ((RTCVideoTrack) -> Void)?
    var onConnectionStateChanged: ((StreamingState) -> Void)?
    
    // Multipeer Connectivity
    private let serviceType = "ar-surface-cap"
    private var peerId: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    // WebRTC
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var localVideoSource: RTCVideoSource?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    
    private var dataChannel: RTCDataChannel?
    private var localSdp: RTCSessionDescription?
    private var remotePeer: MCPeerID?
    
    // ICE candidates queue until SDP exchange is done
    private var pendingIceCandidates = [RTCIceCandidate]()
    private var isSDPExchangeComplete = false
    
    // Quality settings
    private var videoQuality: VideoQuality = .high
    
    // Track connection statistics for debugging
    private var trackStatsTimers = Set<Timer>()
    private var statsTimeReference: Date?
    
    // Initializer
    override init() {
        self.peerId = MCPeerID(displayName: UIDevice.current.name)
        self.session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        
        super.init()
        
        self.session.delegate = self
        
        // Initialize WebRTC
        initializeWebRTC()
        setupVideoTrackHandling()
    }
    
    // Setup WebRTC components
    private func initializeWebRTC() {
        print("WebRTC: Initializing components...")
        
        // Initialize RTCPeerConnectionFactory with default encoders and decoders
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        
        peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        
        // Configure logging
        RTCSetMinDebugLogLevel(.verbose)
        print("WebRTC: Factory created")
    }
    
    private func setupVideoTrackHandling() {
        onRemoteVideoTrackReceived = { [weak self] videoTrack in
            guard let self = self else { return }
            
            print("WebRTC: Received remote video track")
            print("WebRTC: Video Track Details:")
            print("  - Track ID: \(videoTrack.trackId)")
            print("  - Track Enabled: \(videoTrack.isEnabled)")
            
            // Enable the track to ensure it's active
            videoTrack.isEnabled = true
            
            // Store the track
            self.remoteVideoTrack = videoTrack
            
            // Notify any UI observers that we've received a track
            DispatchQueue.main.async {
                self.isConnected = true
                self.streamingState = .connected
                self.onConnectionStateChanged?(.connected)
            }
            
            // Start monitoring track stats
            self.startTrackStatsMonitoring(videoTrack)
        }
    }

    // Monitor video track statistics to help diagnose streaming issues
    private func startTrackStatsMonitoring(_ track: RTCVideoTrack) {
        guard let connection = peerConnection else { return }
        
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak connection, weak track] _ in
            guard let connection = connection, let track = track else { return }
            
            // Request key frame periodically to ensure video flows
            if let _ = self?.remoteVideoTrack, self?.isConnected == true {
                // This can help kickstart video if it's stalled
                track.isEnabled = false
                track.isEnabled = true
            }
            
            connection.statistics { stats in
                print("WebRTC Video Track Stats:")
                
                var hasVideoStats = false
                var totalBytesReceived: Int64 = 0
                
                stats.statistics.forEach { (statsId, statsObj) in
                    if statsObj.type == "inbound-rtp" && statsObj.values["mediaType"] as? String == "video" {
                        hasVideoStats = true
                        
                        if let frameWidth = statsObj.values["frameWidth"] as? Int32,
                           let frameHeight = statsObj.values["frameHeight"] as? Int32 {
                            print("  Resolution: \(frameWidth)x\(frameHeight)")
                        }
                        
                        if let framesDecoded = statsObj.values["framesDecoded"] as? Int32 {
                            print("  Frames Decoded: \(framesDecoded)")
                        }
                        
                        if let packetsLost = statsObj.values["packetsLost"] as? Int32 {
                            print("  Packets Lost: \(packetsLost)")
                        }
                        
                        if let bytesReceived = statsObj.values["bytesReceived"] as? Int64 {
                            totalBytesReceived = bytesReceived
                            print("  Bytes Received: \(bytesReceived)")
                        }
                    }
                }
                
                print("  Track Enabled: \(track.isEnabled)")
                print("  Total Bytes Received: \(totalBytesReceived)")
                
                if !hasVideoStats {
                    print("No video stats available - stream may not be flowing")
                }
            }
        }
        
        // Store timer to prevent deallocation
        trackStatsTimers.insert(timer)
    }
    
    // Start hosting a streaming session
    func startHosting(withDirectCameraAccess: Bool = false) {
        print("WebRTC: Starting hosting...")
        guard streamingState == .idle || streamingState == .failed else {
            print("Cannot start hosting - state is \(streamingState)")
            return
        }
        
        // Initialize WebRTC components
        print("WebRTC: Initializing components...")
        if peerConnectionFactory == nil {
            print("WebRTC: Creating factory...")
            initializeWebRTC()
        }
        
        stopCurrentSession()
        
        isHosting = true
        useDirectCamera = withDirectCameraAccess
        streamingState = .hosting
        
        // Start advertising over multipeer connectivity
        print("WebRTC: Starting advertising...")
        advertiser = MCNearbyServiceAdvertiser(peer: peerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        // Set up as host
        print("WebRTC: Setting up as host...")
        setupAsHost()
        
        // Only start camera capture if we're using direct camera access
        if withDirectCameraAccess {
            print("WebRTC: Starting direct camera capture...")
            startDirectCameraCapture()
        }
        
        onConnectionStateChanged?(.hosting)
    }
    
    private var useDirectCamera: Bool = false
    
    private func startDirectCameraCapture() {
        guard let factory = peerConnectionFactory, let videoSource = localVideoSource else {
            errorMessage = "Video source not initialized"
            print("ERROR: Cannot start video capture - factory or source is nil")
            return
        }
        
        // Create camera capturer
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        
        // Get capture device
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            print("ERROR: Failed to get capture device")
            return
        }
        
        print("📷 Capture Device: \(captureDevice.localizedName)")
        print("📷 Position: \(captureDevice.position)")
        
        // Get available formats for the device
        let formats = RTCCameraVideoCapturer.supportedFormats(for: captureDevice)
        print("🎥 Available Formats: \(formats.count)")
        
        // Find a suitable format - prioritizing stability over quality initially
        var selectedFormat: AVCaptureDevice.Format?
        var selectedFrameRate: Int = 30
        
        // First pass: Look for 640x480 or similar mid-resolution format
        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let frameRates = format.videoSupportedFrameRateRanges
            
            print("🔍 Checking Format: \(dimensions.width)x\(dimensions.height)")
            print("🔍 Frame Rates: \(frameRates)")
            
            // Target 640x480 @ 30fps - this is reliable for most devices
            if dimensions.width == 640 && dimensions.height == 480 {
                for range in frameRates {
                    if range.maxFrameRate >= 30.0 {
                        selectedFormat = format
                        selectedFrameRate = 30
                        break
                    }
                }
                if selectedFormat != nil { break }
            }
        }
        
        // If no 640x480 format found, try for something similar
        if selectedFormat == nil {
            for format in formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let frameRates = format.videoSupportedFrameRateRanges
                
                if dimensions.width >= 480 && dimensions.height >= 360 {
                    for range in frameRates {
                        if range.maxFrameRate >= 30.0 {
                            selectedFormat = format
                            selectedFrameRate = 30
                            break
                        }
                    }
                    if selectedFormat != nil { break }
                }
            }
        }
        
        // If still no format, use the first one
        if selectedFormat == nil && !formats.isEmpty {
            selectedFormat = formats.first
            let dimensions = CMVideoFormatDescriptionGetDimensions(formats.first!.formatDescription)
            let frameRates = formats.first!.videoSupportedFrameRateRanges
            selectedFrameRate = Int(min(frameRates.first?.maxFrameRate ?? 30.0, 30.0))
        }
        
        // Start capturing with the selected format
        if let format = selectedFormat, let capturer = videoCapturer {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFrameRate = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30.0
            
            print("✅ Selected Format:")
            print("   Resolution: \(dimensions.width)x\(dimensions.height)")
            print("   Max Frame Rate: \(maxFrameRate)")
            
            // Start capture with explicit error handling
            capturer.startCapture(with: captureDevice,
                                 format: format,
                                 fps: selectedFrameRate) { error in
                if let error = error {
                    print("❌ ERROR starting capture: \(error)")
                } else {
                    print("✅ VIDEO CAPTURE STARTED SUCCESSFULLY")
                }
            }
        } else {
            print("No suitable camera format found")
            errorMessage = "No suitable camera format found"
        }
    }
    
    // Start joining an existing streaming session
    func startJoining() {
        guard streamingState == .idle || streamingState == .failed else { return }
        
        stopCurrentSession()
        
        isJoining = true
        streamingState = .joining
        
        // Start browsing for peers
        browser = MCNearbyServiceBrowser(peer: peerId, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        onConnectionStateChanged?(.joining)
    }
    
    // Connect to a specific peer
    func connectToPeer(_ peer: MCPeerID) {
        guard isJoining else { return }
        
        // Setup video track handling before establishing connection
        setupVideoTrackHandling()
        
        print("WebRTC: Connecting to peer: \(peer.displayName)")
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
        remotePeer = peer
    }
    
    var connectedPeersCount: Int {
        return session.connectedPeers.count
    }
    
    // Disconnect from current session
    // Make sure to stop camera when disconnecting
    func disconnect() {
        // Stop video capture first with proper callback handling
        if useDirectCamera && videoCapturer != nil {
            print("WebRTC: Stopping capture...")
            videoCapturer?.stopCapture { [weak self] in
                print("Camera capture stopped")
                // Continue disconnection after camera is fully stopped
                self?.finishDisconnect()
            }
        } else {
            finishDisconnect()
        }
    }

    // Helper method to finish disconnection after camera is stopped
    private func finishDisconnect() {
        stopCurrentSession()
        
        // Cancel all stats monitoring timers
        for timer in trackStatsTimers {
            timer.invalidate()
        }
        trackStatsTimers.removeAll()
        
        isHosting = false
        isJoining = false
        isConnected = false
        useDirectCamera = false
        streamingState = .idle
        remotePeer = nil
                
        onConnectionStateChanged?(.idle)
    }
    
    // Stop and clean up current session
    private func stopCurrentSession() {
        // Stop advertising/browsing
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        
        browser?.stopBrowsingForPeers()
        browser = nil
        
        // Close WebRTC connections
        closeWebRTCConnection()
        
        // Reset session
        session.disconnect()
        session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // Reset state variables
        pendingIceCandidates.removeAll()
        isSDPExchangeComplete = false
        localSdp = nil
    }
    
    // Clean up WebRTC connections
    private func closeWebRTCConnection() {
        // Stop local video
        if let capturer = videoCapturer {
            print("Stopping video capturer...")
            capturer.stopCapture(completionHandler: {
                print("Video capture stopped")
            })
        }
        videoCapturer = nil
        
        // Close peer connection
        if let connection = peerConnection {
            connection.close()
        }
        peerConnection = nil
        
        // Clean up tracks
        localVideoTrack = nil
        remoteVideoTrack = nil
        localVideoSource = nil
        dataChannel = nil
    }
    
    // MARK: - WebRTC Setup Methods
    
    // Create peer connection with ICE servers
    private func createPeerConnection() -> RTCPeerConnection? {
        print("WebRTC: Creating peer connection")
        let config = RTCConfiguration()
        
        // Set up STUN/TURN servers for NAT traversal
        // Using multiple STUN servers improves connectivity chances
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun2.l.google.com:19302"])
        ]
        
        // Set ICE transport policy
        config.iceTransportPolicy = .all
        
        // Enable continual ICE gathering
        config.continualGatheringPolicy = .gatherContinually
        
        // Set up peer connection constraints
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["DtlsSrtpKeyAgreement": "true"],
            optionalConstraints: ["RtpDataChannels": "true"]
        )
        
        // Create peer connection
        guard let peerConnection = peerConnectionFactory?.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else {
            errorMessage = "Failed to create peer connection"
            print("WebRTC: Failed to create peer connection")
            return nil
        }
        
        print("WebRTC: Peer connection created successfully")
        return peerConnection
    }
    
    // Set up local media tracks
    private func setupLocalMediaTracks() {
        guard let factory = peerConnectionFactory else {
            print("ERROR: Cannot setup media tracks - factory is nil")
            return
        }
        
        print("🔧 Setting up local media tracks")
        
        // Create local video source
        localVideoSource = factory.videoSource()
        
        guard let videoSource = localVideoSource else {
            print("ERROR: Failed to create video source")
            return
        }
        
        // Create video track from source
        let videoTrackId = "WebRTC_Video_" + UUID().uuidString
        localVideoTrack = factory.videoTrack(with: videoSource, trackId: videoTrackId)
        print("✅ Created video track: \(videoTrackId)")
        
        // Add tracks to peer connection
        if let peerConnection = peerConnection, let videoTrack = localVideoTrack {
            let sender = peerConnection.add(videoTrack, streamIds: ["ARKitStream"])
            print("🔗 Added video track to peer connection: \(sender)")
        }
    }
    
    func logConnectionStatus() {
        print("\n--- WebRTC Connection Status ---")
        print("Is Hosting: \(isHosting)")
        print("Is Joining: \(isJoining)")
        print("Is Connected: \(isConnected)")
        print("Streaming State: \(streamingState)")
        print("Error Message: \(errorMessage ?? "None")")
        print("Available Peers: \(availablePeers.count)")
        print("Connected Peers: \(connectedPeersCount)")
        
        if let connection = peerConnection {
            print("Peer Connection State: \(connection.connectionState.rawValue)")
            print("Signaling State: \(connection.signalingState.rawValue)")
            print("ICE Connection State: \(connection.iceConnectionState.rawValue)")
            print("ICE Gathering State: \(connection.iceGatheringState.rawValue)")
            
            // Get stats about the connection
            connection.statistics { stats in
                print("\n--- WebRTC Stats ---")
                
                stats.statistics.forEach { (statsId, statsObj) in
                    if statsObj.type == "inbound-rtp" && statsObj.values["mediaType"] as? String == "video" {
                        print("Video Stats (Inbound):")
                        if let frameWidth = statsObj.values["frameWidth"] as? Int32,
                           let frameHeight = statsObj.values["frameHeight"] as? Int32 {
                            print("  Resolution: \(frameWidth)x\(frameHeight)")
                        }
                        
                        if let framesDecoded = statsObj.values["framesDecoded"] as? Int32 {
                            print("  Frames decoded: \(framesDecoded)")
                        }
                        
                        if let bytesReceived = statsObj.values["bytesReceived"] as? Int64 {
                            print("  Bytes received: \(bytesReceived)")
                        }
                    } else if statsObj.type == "outbound-rtp" && statsObj.values["mediaType"] as? String == "video" {
                        print("Video Stats (Outbound):")
                        if let frameWidth = statsObj.values["frameWidth"] as? Int32,
                           let frameHeight = statsObj.values["frameHeight"] as? Int32 {
                            print("  Resolution: \(frameWidth)x\(frameHeight)")
                        }
                        
                        if let framesEncoded = statsObj.values["framesEncoded"] as? Int32 {
                            print("  Frames encoded: \(framesEncoded)")
                        }
                        
                        if let bytesSent = statsObj.values["bytesSent"] as? Int64 {
                            print("  Bytes sent: \(bytesSent)")
                        }
                    }
                }
                
                print("--- End WebRTC Stats ---\n")
            }
        } else {
            print("No peer connection established")
        }
        print("--- End WebRTC Connection Status ---\n")
    }
    
    // Start capturing local video
    private func startLocalVideoCapture() {
        guard let factory = peerConnectionFactory, let videoSource = localVideoSource else {
            errorMessage = "Video source not initialized"
            print("ERROR: Cannot start video capture - factory or source is nil")
            return
        }
        
        // Create camera capturer with robust device selection
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        
        guard let capturer = videoCapturer else {
            errorMessage = "Failed to create video capturer"
            return
        }
        
        let captureDevices = RTCCameraVideoCapturer.captureDevices()
        guard let backCamera = captureDevices.first(where: { $0.position == .back }) ?? captureDevices.first else {
            errorMessage = "No camera available"
            return
        }
        
        let formats = RTCCameraVideoCapturer.supportedFormats(for: backCamera)
        
        // Prioritize 720p or 480p format with 30fps for reliability
        let targetFormats = formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let frameRates = format.videoSupportedFrameRateRanges
            
            return (dimensions.width == 1280 && dimensions.height == 720) ||
                   (dimensions.width == 640 && dimensions.height == 480) &&
                   frameRates.contains(where: { $0.maxFrameRate >= 30 })
        }
        
        guard let selectedFormat = targetFormats.first ?? formats.first else {
            errorMessage = "No suitable video format found"
            return
        }
        
        // Start capture with detailed error logging
        let dimensions = CMVideoFormatDescriptionGetDimensions(selectedFormat.formatDescription)
        let fps = 30 // Target 30fps for reliability
        
        capturer.startCapture(
            with: backCamera,
            format: selectedFormat,
            fps: fps
        ) { error in
            if let error = error {
                print("ERROR: Failed to start video capture: \(error)")
                self.errorMessage = "Video capture initialization failed"
            } else {
                print("Video capture started successfully")
            }
        }
    }
    
    // Set up WebRTC connection as offerer (host)
    private func setupAsHost() {
        guard let peerFactory = peerConnectionFactory else {
            print("ERROR: PeerConnectionFactory is nil")
            errorMessage = "Failed to initialize WebRTC"
            return
        }
        
        // Create peer connection
        peerConnection = createPeerConnection()
        if peerConnection == nil {
            print("ERROR: Failed to create peer connection")
            errorMessage = "Failed to create WebRTC connection"
            return
        }
        
        // Set up local media - make sure video track is properly created
        setupLocalMediaTracks()
        
        // Create data channel
        if let peerConnection = peerConnection {
            let config = RTCDataChannelConfiguration()
            config.isOrdered = true
            
            dataChannel = peerConnection.dataChannel(forLabel: "ARDataChannel", configuration: config)
            dataChannel?.delegate = self
        }
    }
    
    // Set up WebRTC connection as answerer (joiner)
    private func setupAsJoiner() {
        guard let peerFactory = peerConnectionFactory else { return }
        
        // Create peer connection
        peerConnection = createPeerConnection()
    }
    
    // Create and send offer (for host)
    func createAndSendOffer() {
        guard let peerConnection = peerConnection else { return }
        
        // Create constraints - set OfferToReceiveAudio to false
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )
        
        // Create offer
        peerConnection.offer(for: constraints) { [weak self] (sdp, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Failed to create offer: \(error.localizedDescription)"
                return
            }
            
            guard let sdp = sdp else { return }
            
            // Set local description
            peerConnection.setLocalDescription(sdp) { [weak self] error in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = "Failed to set local description: \(error.localizedDescription)"
                    return
                }
                
                // Store local SDP
                self.localSdp = sdp
                
                // Send offer to remote peer
                self.sendSDPToPeer(sdp)
            }
        }
    }
    
    // Handle received offer (for joiner)
    func handleReceivedOffer(_ offerSdp: RTCSessionDescription) {
        guard let peerConnection = peerConnection else { return }
        
        // Set remote description
        peerConnection.setRemoteDescription(offerSdp) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Failed to set remote description: \(error.localizedDescription)"
                return
            }
            
            // Create answer
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": "false",
                    "OfferToReceiveVideo": "true"
                ],
                optionalConstraints: nil
            )
            
            peerConnection.answer(for: constraints) { [weak self] (sdp, error) in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = "Failed to create answer: \(error.localizedDescription)"
                    return
                }
                
                guard let sdp = sdp else { return }
                
                // Set local description
                peerConnection.setLocalDescription(sdp) { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.errorMessage = "Failed to set local description: \(error.localizedDescription)"
                        return
                    }
                    
                    // Store local SDP
                    self.localSdp = sdp
                    
                    // Send answer to remote peer
                    self.sendSDPToPeer(sdp)
                }
            }
        }
    }
    
    // Handle received answer (for host)
    func handleReceivedAnswer(_ answerSdp: RTCSessionDescription) {
        guard let peerConnection = peerConnection else { return }
        
        // Set remote description
        peerConnection.setRemoteDescription(answerSdp) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Failed to set remote description: \(error.localizedDescription)"
                return
            }
            
            self.isSDPExchangeComplete = true
            
            // Process any pending ICE candidates
            for candidate in self.pendingIceCandidates {
                self.peerConnection?.add(candidate) { error in
                    if let error = error {
                        print("Failed to add ICE candidate: \(error)")
                    }
                }
            }
            self.pendingIceCandidates.removeAll()
        }
    }
    
    // Handle ICE candidate
    func handleICECandidate(_ iceCandidate: RTCIceCandidate) {
        if isSDPExchangeComplete {
            peerConnection?.add(iceCandidate) { error in
                if let error = error {
                    print("Failed to add ICE candidate: \(error)")
                }
            }
        } else {
            pendingIceCandidates.append(iceCandidate)
        }
    }
    
    // MARK: - Data Transmission Methods
    
    // Send SDP to peer using MultipeerConnectivity
    private func sendSDPToPeer(_ sdp: RTCSessionDescription) {
        guard let remotePeer = remotePeer, session.connectedPeers.contains(remotePeer) else {
            errorMessage = "No connected peer to send SDP"
            return
        }
        
        do {
            // Convert SDP to dictionary
            let type = sdp.type == .offer ? "offer" : "answer"
            let sdpDict: [String: Any] = [
                "type": type,
                "sdp": sdp.sdp
            ]
            
            // Create message with message type
            let message: [String: Any] = [
                "messageType": "sdp",
                "data": sdpDict
            ]
            
            // Serialize to JSON
            let data = try JSONSerialization.data(withJSONObject: message)
            
            // Send to peer
            try session.send(data, toPeers: [remotePeer], with: .reliable)
        } catch {
            errorMessage = "Failed to send SDP: \(error.localizedDescription)"
        }
    }
    
    // Send ICE candidate to peer
    private func sendICECandidate(_ candidate: RTCIceCandidate, to peer: MCPeerID) {
        do {
            // Convert candidate to dictionary
            let candidateDict: [String: Any] = [
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdp": candidate.sdp
            ]
            
            // Create message with message type
            let message: [String: Any] = [
                "messageType": "candidate",
                "data": candidateDict
            ]
            
            // Serialize to JSON
            let data = try JSONSerialization.data(withJSONObject: message)
            
            // Send to peer
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            errorMessage = "Failed to send ICE candidate: \(error.localizedDescription)"
        }
    }
    
    // Process received data from peer
    private func processReceivedData(_ data: Data, from peer: MCPeerID) {
        do {
            guard let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messageType = message["messageType"] as? String,
                  let messageData = message["data"] as? [String: Any] else {
                errorMessage = "Received invalid message format"
                return
            }
            
            switch messageType {
            case "sdp":
                guard let sdpType = messageData["type"] as? String,
                      let sdpString = messageData["sdp"] as? String else {
                    errorMessage = "Invalid SDP format"
                    return
                }
                
                let type: RTCSdpType = sdpType == "offer" ? .offer : .answer
                let sdp = RTCSessionDescription(type: type, sdp: sdpString)
                
                DispatchQueue.main.async {
                    if type == .offer {
                        self.handleReceivedOffer(sdp)
                    } else {
                        self.handleReceivedAnswer(sdp)
                    }
                }
                
            case "candidate":
                guard let sdpMid = messageData["sdpMid"] as? String,
                      let sdpMLineIndex = messageData["sdpMLineIndex"] as? Int32,
                      let sdpString = messageData["sdp"] as? String else {
                    errorMessage = "Invalid candidate format"
                    return
                }
                
                let candidate = RTCIceCandidate(sdp: sdpString, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
                
                DispatchQueue.main.async {
                    self.handleICECandidate(candidate)
                }
                
            default:
                errorMessage = "Unknown message type: \(messageType)"
            }
        } catch {
            errorMessage = "Failed to process received data: \(error.localizedDescription)"
        }
    }
    
    // Get connection statistics
    func getStats(completion: @escaping (RTCStatisticsReport) -> Void) {
        peerConnection?.statistics { stats in
            completion(stats)
        }
    }
    
    // Set video quality
    func setVideoQuality(_ quality: VideoQuality) {
        self.videoQuality = quality
        
        // If we're already streaming, restart capture with new quality
        if isHosting, let capturer = videoCapturer {
            capturer.stopCapture {
                self.startLocalVideoCapture()
            }
        }
    }
    
    // MARK: - Utility Enums and Structs
    
    enum VideoQuality {
        case low    // 640x480 or similar
        case medium // 1280x720 or similar
        case high   // 1920x1080 or higher
    }
}

// MARK: - MCSessionDelegate
extension WebRTCService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.remotePeer = peerID
                
                // Set up WebRTC connection based on role
                if self.isHosting {
                    self.setupAsHost()
                    // Create and send offer after a short delay to ensure connection is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.createAndSendOffer()
                    }
                } else if self.isJoining {
                    self.setupAsJoiner()
                    // Wait for offer from host
                }
                
                self.isConnected = true
                self.streamingState = .connected
                self.onConnectionStateChanged?(.connected)
                
            case .connecting:
                print("Peer is connecting: \(peerID.displayName)")
                
            case .notConnected:
                if peerID == self.remotePeer {
                    self.disconnect()
                }
                
            @unknown default:
                print("Unknown session state: \(state)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Process received WebRTC signaling data
        processReceivedData(data, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension WebRTCService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept incoming connection requests
        invitationHandler(true, session)
        remotePeer = peerID
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Failed to start advertising: \(error.localizedDescription)"
            self.streamingState = .failed
            self.onConnectionStateChanged?(.failed)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension WebRTCService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.availablePeers.contains(peerID) {
                self.availablePeers.append(peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
            
            if peerID == self.remotePeer {
                self.disconnect()
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Failed to start browsing: \(error.localizedDescription)"
            self.streamingState = .failed
            self.onConnectionStateChanged?(.failed)
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension WebRTCService: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state changed: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            print("Peer connection state changed: \(state.rawValue)")
            
            switch state {
            case .failed:
                self.errorMessage = "WebRTC connection failed"
                self.streamingState = .failed
                self.onConnectionStateChanged?(.failed)
                
            case .disconnected:
                if self.isConnected {
                    self.streamingState = .failed
                    self.onConnectionStateChanged?(.failed)
                }
                
            case .connected:
                self.streamingState = .connected
                self.onConnectionStateChanged?(.connected)
                
            default:
                break
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCIceConnectionState) {
        DispatchQueue.main.async {
            print("ICE connection state changed: \(stateChanged.rawValue)")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        DispatchQueue.main.async {
            print("ICE gathering state changed: \(newState.rawValue)")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
            guard let remotePeer = self.remotePeer else { return }
            self.sendICECandidate(candidate, to: remotePeer)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Not implemented in this example
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            self.dataChannel = dataChannel
            dataChannel.delegate = self
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        DispatchQueue.main.async {
            if let videoTrack = stream.videoTracks.first {
                self.remoteVideoTrack = videoTrack
                self.onRemoteVideoTrackReceived?(videoTrack)
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self.remoteVideoTrack = nil
        }
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Handle renegotiation if needed
    }
    
    // For RTCPeerConnectionDelegate conformance
    func peerConnectionDidChangeSignalingState(_ peerConnection: RTCPeerConnection) {
        // Implementation to match protocol
    }

    func peerConnectionDidChangeIceGatheringState(_ peerConnection: RTCPeerConnection) {
        // Implementation to match protocol
    }

    func peerConnectionDidChangeIceConnectionState(_ peerConnection: RTCPeerConnection) {
        // Implementation to match protocol
    }
}

// MARK: - RTCDataChannelDelegate
extension WebRTCService: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("Data channel state changed: \(dataChannel.readyState)")
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        // Handle data channel messages if needed
        if let message = String(data: buffer.data, encoding: .utf8) {
            print("Received data channel message: \(message)")
        }
    }
}
