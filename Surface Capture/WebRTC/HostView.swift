//
//  HostView.swift
//  CameraStreamer
//
//  Created by Ashley Davison on 28/03/2025.
//

import SwiftUI
import AVFoundation
import WebRTC
import MultipeerConnectivity

struct HostView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = HostViewModel()
    
    // Add onClose callback to communicate back to parent view
    var onClose: () -> Void
    
    var body: some View {
        ZStack {
            // Camera preview handled by UIViewRepresentable
            CameraPreviewView(captureSession: viewModel.captureSession)
                .ignoresSafeArea()
            
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
                
                // Close button
                Button(action: {
                    // Stop capture and advertising
                    viewModel.stopCapture()
                    viewModel.stopAdvertising()
                    
                    // Call the onClose callback to notify parent view
                    onClose()
                    
                    // Dismiss this view
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 40)
                        .background(Color.red.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.bottom, 20)
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.setupMultipeerConnectivity()
            viewModel.setupWebRTC()
            viewModel.setupCamera()
        }
        .onDisappear {
            viewModel.stopCapture()
            viewModel.stopAdvertising()
        }
    }
}

// UIViewRepresentable for AVCaptureSession preview
struct CameraPreviewView: UIViewRepresentable {
    var captureSession: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect.zero)
        view.backgroundColor = .black
        
        if let captureSession = captureSession {
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
            
            // Use the updated notification name for iOS 18
            let notificationName: NSNotification.Name
            if #available(iOS 18.0, *) {
                notificationName = AVCaptureSession.didStartRunningNotification
            } else {
                notificationName = NSNotification.Name.AVCaptureSessionDidStartRunning
            }
            
            NotificationCenter.default.addObserver(forName: notificationName,
                                                  object: captureSession,
                                                  queue: nil) { _ in
                DispatchQueue.main.async {
                    previewLayer.frame = view.bounds
                }
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}

class HostViewModel: NSObject, ObservableObject {
    @Published var statusMessage = "Waiting for peer to connect..."
    
    var session: MCSession?
    var peerID: MCPeerID?
    var serviceAdvertiser: MCNearbyServiceAdvertiser?
    
    var captureSession: AVCaptureSession?
    var videoOutput: AVCaptureVideoDataOutput?
    
    var peerConnection: RTCPeerConnection?
    var factory: RTCPeerConnectionFactory?
    var videoSource: RTCVideoSource?
    var localVideoTrack: RTCVideoTrack?
    var dataChannel: RTCDataChannel?
    var videoCapturer: RTCVideoCapturer?
    
    func setupMultipeerConnectivity() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID!, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID!, discoveryInfo: ["type": "host"], serviceType: "webrtc-stream")
        serviceAdvertiser?.delegate = self
        startAdvertising()
    }
    
    func setupWebRTC() {
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"])
        
        peerConnection = factory?.peerConnection(with: config, constraints: constraints, delegate: self)
        
        videoSource = factory?.videoSource()
        
        // Create a video capturer
        videoCapturer = RTCCameraVideoCapturer()
        
        // Increase to 4K resolution (3840x2160)
        videoSource?.adaptOutputFormat(toWidth: 3840, height: 2160, fps: 24)
        
        let videoTrackID = "video0"
        localVideoTrack = factory?.videoTrack(with: videoSource!, trackId: videoTrackID)
        
        let streamID = "stream0"
        peerConnection?.add(localVideoTrack!, streamIds: [streamID])
        
        let dataChannelConfig = RTCDataChannelConfiguration()
        dataChannelConfig.isOrdered = false
        dataChannelConfig.maxRetransmits = 0
        dataChannel = peerConnection?.dataChannel(forLabel: "data", configuration: dataChannelConfig)
    }
    
    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .hd4K3840x2160
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Failed to get camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    func createOffer() {
        // Configure SDP with higher bitrate for 4K
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "false",
            "OfferToReceiveVideo": "true"
        ], optionalConstraints: [
            "maxBitrate": "8000000",  // 8 Mbps for 4K
            "maxFramerate": "30"
        ])
        
        peerConnection?.offer(for: constraints) { [weak self] (sdp, error) in
            guard let sdp = sdp, error == nil else {
                print("Failed to create offer: \(error?.localizedDescription ?? "unknown error")")
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
    
    func startAdvertising() {
        serviceAdvertiser?.startAdvertisingPeer()
    }
    
    func stopAdvertising() {
        serviceAdvertiser?.stopAdvertisingPeer()
    }
    
    func stopCapture() {
        captureSession?.stopRunning()
    }
}

extension HostViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timeStampNs = Int64(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000000000)
        let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: ._0, timeStampNs: timeStampNs)
        
        videoSource?.capturer(videoCapturer!, didCapture: videoFrame)
    }
}

extension HostViewModel: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error)")
    }
}

extension HostViewModel: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                self?.statusMessage = "Connected to \(peerID.displayName)"
                self?.createOffer()
            case .connecting:
                self?.statusMessage = "Connecting to \(peerID.displayName)..."
            case .notConnected:
                self?.statusMessage = "Disconnected from \(peerID.displayName)"
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
                peerConnection?.setRemoteDescription(description) { error in
                    if let error = error {
                        print("Failed to set remote description: \(error)")
                    }
                }
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension HostViewModel: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("Signaling state changed: \(stateChanged.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            switch newState {
            case .connected:
                self?.statusMessage = "ICE Connected"
            case .disconnected:
                self?.statusMessage = "ICE Disconnected"
            case .failed:
                self?.statusMessage = "ICE Connection Failed"
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
}
