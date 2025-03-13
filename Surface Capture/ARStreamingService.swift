//
//  ARStreamingService.swift
//  Surface Capture
//

import Foundation
import RealityKit
import ARKit
import MultipeerConnectivity
import Combine

/// Service to handle AR streaming between devices
class ARStreamingService: NSObject, ObservableObject {
    // MARK: - Public Properties
    
    /// Published properties for UI updates
    @Published var isHosting = false
    @Published var isJoining = false
    @Published var isConnected = false
    @Published var peers: [MCPeerID] = []
    @Published var errorMessage: String?
    @Published var sessionState: SessionState = .idle
    
    /// Callback when a transform is received from a peer
    var onReceivedTransform: ((Transform) -> Void)?
    
    /// Callback when a world map is received from a peer
    var onReceivedWorldMap: ((ARWorldMap) -> Void)?
    
    // MARK: - Private Properties
    
    private let serviceType = "ar-surface-cap"
    private let peerId = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var serviceAdvertiser: MCNearbyServiceAdvertiser?
    private var serviceBrowser: MCNearbyServiceBrowser?
    
    private var arView: ARView?
    private var modelEntity: ModelEntity?
    private var streamingCancellable: Cancellable?
    private var worldMapCancellable: AnyCancellable?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSession()
    }
    
    // MARK: - Public Methods
    
    /// Start hosting a session to share AR content
    func startHosting() {
        guard sessionState == .idle || sessionState == .failed else { return }
        
        sessionState = .starting
        
        stopBrowsing()
        
        serviceAdvertiser = MCNearbyServiceAdvertiser(
            peer: peerId,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        serviceAdvertiser?.delegate = self
        serviceAdvertiser?.startAdvertisingPeer()
        
        isHosting = true
        isJoining = false
        
        sessionState = .hosting
    }
    
    /// Start joining an existing AR sharing session
    func startJoining() {
        guard sessionState == .idle || sessionState == .failed else { return }
        
        sessionState = .starting
        
        stopAdvertising()
        
        serviceBrowser = MCNearbyServiceBrowser(peer: peerId, serviceType: serviceType)
        serviceBrowser?.delegate = self
        serviceBrowser?.startBrowsingForPeers()
        
        isHosting = false
        isJoining = true
        
        sessionState = .joining
    }
    
    /// Start streaming AR content
    func startStreaming(arView: ARView, modelEntity: ModelEntity) {
        self.arView = arView
        self.modelEntity = modelEntity
        
        // Stream model transform updates
        streamingCancellable = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            guard let self = self, let modelEntity = self.modelEntity else { return }
            
            let modelTransform = modelEntity.transform
            self.sendTransform(modelTransform)
        }
        
        // Try to get and send world map
        sendWorldMap()
    }
    
    /// Stop streaming AR content
    func stopStreaming() {
        streamingCancellable?.cancel()
        streamingCancellable = nil
        worldMapCancellable?.cancel()
        worldMapCancellable = nil
        
        arView = nil
        modelEntity = nil
    }
    
    /// Disconnect from the current session
    func disconnect() {
        stopStreaming()
        stopAdvertising()
        stopBrowsing()
        
        session?.disconnect()
        setupSession() // Create a fresh session
        
        isHosting = false
        isJoining = false
        isConnected = false
        sessionState = .idle
        peers = []
        errorMessage = nil
    }
    
    // MARK: - Private Methods
    
    private func setupSession() {
        let session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
    }
    
    private func stopAdvertising() {
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceAdvertiser = nil
    }
    
    private func stopBrowsing() {
        serviceBrowser?.stopBrowsingForPeers()
        serviceBrowser = nil
    }
    
    private func sendTransform(_ transform: Transform) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        do {
            // Convert Transform to Data
            let transformData = try JSONEncoder().encode(TransformData(from: transform))
            let message = StreamMessage.modelTransform(transformData)
            let messageData = try JSONEncoder().encode(message)
            
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Error sending transform: \(error)")
            errorMessage = "Failed to send transform: \(error.localizedDescription)"
        }
    }
    
    private func sendWorldMap() {
        guard let arView = arView else { return }
        
        // No need to unwrap session as it's not optional on ARView
        let arSession = arView.session
        
        worldMapCancellable = Future<ARWorldMap, Error> { promise in
            arSession.getCurrentWorldMap { worldMap, error in
                if let error = error {
                    promise(.failure(error))
                } else if let worldMap = worldMap {
                    promise(.success(worldMap))
                } else {
                    promise(.failure(NSError(domain: "ARStreamingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error getting world map"])))
                }
            }
        }
        .sink(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    print("Error getting world map: \(error)")
                    self?.errorMessage = "Failed to get world map: \(error.localizedDescription)"
                }
            },
            receiveValue: { [weak self] worldMap in
                self?.sendWorldMapData(worldMap)
            }
        )
    }
    
    private func sendWorldMapData(_ worldMap: ARWorldMap) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        do {
            // Archive the world map
            let worldMapData = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
            let message = StreamMessage.worldMap(worldMapData)
            let messageData = try JSONEncoder().encode(message)
            
            // Send the data
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Error sending world map: \(error)")
            errorMessage = "Failed to send world map: \(error.localizedDescription)"
        }
    }
    
    private func handleReceivedData(_ data: Data, from peer: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(StreamMessage.self, from: data)
            
            switch message {
            case .modelTransform(let transformData):
                let transformData = try JSONDecoder().decode(TransformData.self, from: transformData)
                let transform = transformData.toTransform()
                DispatchQueue.main.async {
                    self.onReceivedTransform?(transform)
                }
                
            case .worldMap(let worldMapData):
                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: worldMapData) else {
                    throw NSError(domain: "ARStreamingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to unarchive world map"])
                }
                
                DispatchQueue.main.async {
                    self.onReceivedWorldMap?(worldMap)
                }
            }
        } catch {
            print("Error processing received data: \(error)")
            errorMessage = "Failed to process received data: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCSessionDelegate

extension ARStreamingService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.peers.contains(peerID) {
                    self.peers.append(peerID)
                }
                
                if !self.peers.isEmpty {
                    self.isConnected = true
                    self.sessionState = .connected
                }
                
            case .connecting:
                // Keep existing state
                break
                
            case .notConnected:
                if let index = self.peers.firstIndex(of: peerID) {
                    self.peers.remove(at: index)
                }
                
                if self.peers.isEmpty {
                    self.isConnected = false
                    
                    // Maintain hosting/joining state
                    if self.isHosting {
                        self.sessionState = .hosting
                    } else if self.isJoining {
                        self.sessionState = .joining
                    } else {
                        self.sessionState = .idle
                    }
                }
            @unknown default:
                print("Unknown MCSession state: \(state)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleReceivedData(data, from: peerID)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ARStreamingService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Failed to start advertising: \(error.localizedDescription)"
            self.sessionState = .failed
            self.isHosting = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension ARStreamingService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Auto-connect to found peers
        browser.invitePeer(peerID, to: session!, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Peer is lost, but the session delegate will handle the actual disconnect
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = "Failed to start browsing: \(error.localizedDescription)"
            self.sessionState = .failed
            self.isJoining = false
        }
    }
}

// MARK: - Helper Types

/// Represents the current state of an AR streaming session
enum SessionState: String, Codable {
    case idle = "Idle"
    case starting = "Starting"
    case hosting = "Hosting"
    case joining = "Joining"
    case connected = "Connected"
    case failed = "Failed"
}

/// Types of messages that can be sent in the stream
enum StreamMessage: Codable {
    case modelTransform(Data)
    case worldMap(Data)
}

/// Codable representation of a RealityKit Transform
struct TransformData: Codable {
    let matrix: [[Float]]
    
    init(from transform: Transform) {
        // Convert the 4x4 transform matrix to a 2D array
        let m = transform.matrix
        self.matrix = [
            [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w],
            [m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w],
            [m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w],
            [m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
        ]
    }
    
    func toTransform() -> Transform {
        // Convert the 2D array back to a 4x4 matrix
        let matrix = simd_float4x4(
            simd_float4(matrix[0][0], matrix[0][1], matrix[0][2], matrix[0][3]),
            simd_float4(matrix[1][0], matrix[1][1], matrix[1][2], matrix[1][3]),
            simd_float4(matrix[2][0], matrix[2][1], matrix[2][2], matrix[2][3]),
            simd_float4(matrix[3][0], matrix[3][1], matrix[3][2], matrix[3][3])
        )
        
        return Transform(matrix: matrix)
    }
}
