//
//  StreamingViewController.swift
//  Surface Capture
//

import UIKit
import SwiftUI
import WebRTC
import Combine

class StreamingViewController: UIViewController {
    // WebRTC service
    private let webRTCService: WebRTCService
    
    private var statsTimeReference: Date?
    private var lastFramesDecoded: Int32?
    
    // Video view
    private lazy var videoView: WebRTCVideoView = {
        let view = WebRTCVideoView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // Loading indicator
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .white
        return indicator
    }()
    
    // Status label
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.isHidden = true
        label.text = "Searching for hosts..."
        return label
    }()
    
    // Back button
    private lazy var backButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(handleBackButton), for: .touchUpInside)
        return button
    }()
    
    // Peer list table for selection
    private lazy var peerListTableView: UITableView = {
        let tableView = UITableView()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        tableView.layer.cornerRadius = 10
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "PeerCell")
        tableView.rowHeight = 60
        tableView.separatorColor = .gray
        tableView.isHidden = true
        return tableView
    }()
    
    // Connection statistics view
    private lazy var statsView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.layer.cornerRadius = 8
        view.isHidden = true
        
        // Add children to stats view
        view.addSubview(statsLabel)
        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            statsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            statsLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
        
        return view
    }()
    
    // Stats label
    private lazy var statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.textAlignment = .left
        label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.numberOfLines = 0
        return label
    }()
    
    // Quality button
    private lazy var qualityButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "dial.high"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(handleQualityButton), for: .touchUpInside)
        button.isHidden = true
        return button
    }()
    
    // Debug information overlay
    private lazy var debugOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        view.layer.cornerRadius = 8
        view.isHidden = true
        
        return view
    }()
    
    // Debug info label
    private lazy var debugLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.textAlignment = .left
        label.font = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.numberOfLines = 0
        label.text = "Waiting for debug info..."
        return label
    }()
    
    // Toggle debug button
    private lazy var debugButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "ladybug"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(handleDebugButton), for: .touchUpInside)
        return button
    }()
    
    // Disconnect completion handler
    private var onDisconnect: (() -> Void)?
    
    // Subscribers for updates
    private var subscribers = Set<AnyCancellable>()
    
    // Stats timer
    private var statsTimer: Timer?
    
    // Flag to track if we've received video frames
    private var hasReceivedFrames: Bool = false
    private var framesReceivedCount: Int32 = 0
    
    // Initializer
    init(webRTCService: WebRTCService, onDisconnect: @escaping () -> Void) {
        self.webRTCService = webRTCService
        self.onDisconnect = onDisconnect
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up UI
        setupUI()
        
        // Set up subscribers
        setupSubscribers()
        
        // Start streaming session
        webRTCService.startJoining()
        
        // Start loading indicator
        loadingIndicator.startAnimating()
        statusLabel.isHidden = false
        statusLabel.text = "Searching for hosts..."
        
        // Update peer table after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updatePeerTableVisibility()
        }
        
        // Setup debug overlay
        setupDebugOverlay()
    }
    
    private func setupDebugOverlay() {
        // Add debug label to debug overlay
        debugOverlay.addSubview(debugLabel)
        
        // Add debug overlay to view
        view.addSubview(debugOverlay)
        view.addSubview(debugButton)
        
        // Configure constraints
        NSLayoutConstraint.activate([
            debugLabel.topAnchor.constraint(equalTo: debugOverlay.topAnchor, constant: 8),
            debugLabel.leadingAnchor.constraint(equalTo: debugOverlay.leadingAnchor, constant: 8),
            debugLabel.trailingAnchor.constraint(equalTo: debugOverlay.trailingAnchor, constant: -8),
            debugLabel.bottomAnchor.constraint(equalTo: debugOverlay.bottomAnchor, constant: -8),
            
            debugOverlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            debugOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            debugOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            debugOverlay.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            
            debugButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            debugButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            debugButton.widthAnchor.constraint(equalToConstant: 40),
            debugButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Hide debug overlay initially
        debugOverlay.isHidden = true
    }
    
    @objc private func handleDebugButton() {
        debugOverlay.isHidden.toggle()
        webRTCService.logConnectionStatus()
        
        // Update debug info
        updateDebugInfo()
    }
    
    private func updateDebugInfo() {
        // Collect debug information
        var debugInfo = "--- WebRTC Debug Info ---\n"
        debugInfo += "State: \(webRTCService.streamingState.rawValue)\n"
        debugInfo += "Connected: \(webRTCService.isConnected)\n"
        debugInfo += "Video Track: \(self.hasReceivedFrames ? "Received" : "Not Received")\n"
        debugInfo += "Frames Decoded: \(self.framesReceivedCount)\n"
        
        // Update the debug label
        debugLabel.text = debugInfo
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Hide navigation bar
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop stats timer
        statsTimer?.invalidate()
        statsTimer = nil
        
        // Clean up WebRTC connection when view disappears
        webRTCService.disconnect()
    }
    
    // Set up UI components
    private func setupUI() {
        // Set background color
        view.backgroundColor = .black
        
        // Add video view as the background with improved setup
        print("StreamingVC: Setting up video view")
        videoView = WebRTCVideoView(frame: .zero)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.backgroundColor = .black
        view.addSubview(videoView)
        
        // Add other UI elements on top
        view.addSubview(loadingIndicator)
        view.addSubview(statusLabel)
        view.addSubview(backButton)
        view.addSubview(peerListTableView)
        view.addSubview(statsView)
        view.addSubview(qualityButton)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            // Video view fills the entire screen
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Center loading indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            // Status label below loading indicator
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            
            // Back button in top-left corner with safe area
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Peer list table in the center of the screen
            peerListTableView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            peerListTableView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            peerListTableView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            peerListTableView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),
            
            // Stats view in the bottom-right corner
            statsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            statsView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.4),
            
            // Quality button in the top-right corner
            qualityButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            qualityButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            qualityButton.widthAnchor.constraint(equalToConstant: 40),
            qualityButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }
    
    // Set up subscribers for WebRTC service updates
    private func setupSubscribers() {
        // Stream state updates
        webRTCService.$streamingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                print("StreamingVC: Streaming state changed to: \(state)")
                self?.handleStreamingStateChange(state)
            }
            .store(in: &subscribers)
        
        // Available peers updates
        webRTCService.$availablePeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                print("StreamingVC: Available peers updated: \(peers.count) peers")
                self?.updatePeerTableVisibility()
                self?.peerListTableView.reloadData()
            }
            .store(in: &subscribers)
        
        // Error message updates
        webRTCService.$errorMessage
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] message in
                print("StreamingVC: Error - \(message)")
                self?.showError(message)
            }
            .store(in: &subscribers)
        
        // Set up callback for receiving remote video track
        webRTCService.onRemoteVideoTrackReceived = { [weak self] videoTrack in
            print("StreamingVC: Remote video track received callback")
            DispatchQueue.main.async {
                self?.handleRemoteVideoTrack(videoTrack)
            }
        }
    }
    
    // Handle streaming state changes
    private func handleStreamingStateChange(_ state: WebRTCService.StreamingState) {
        switch state {
        case .idle:
            statusLabel.text = "Ready to connect"
            loadingIndicator.stopAnimating()
            peerListTableView.isHidden = true
            statsView.isHidden = true
            qualityButton.isHidden = true
            
        case .starting, .joining:
            statusLabel.text = "Connecting..."
            loadingIndicator.startAnimating()
            peerListTableView.isHidden = true
            statsView.isHidden = true
            qualityButton.isHidden = true
            
        case .hosting:
            statusLabel.text = "Hosting session"
            loadingIndicator.stopAnimating()
            peerListTableView.isHidden = true
            statsView.isHidden = true
            qualityButton.isHidden = true
            
        case .connected:
            statusLabel.isHidden = true
            loadingIndicator.stopAnimating()
            peerListTableView.isHidden = true
            updateStatsVisibility(true)
            qualityButton.isHidden = false
            
            // Start stats timer
            startStatsTimer()
            
        case .failed:
            statusLabel.text = "Connection failed"
            loadingIndicator.stopAnimating()
            updatePeerTableVisibility()
            statsView.isHidden = true
            qualityButton.isHidden = true
            
            // Stop stats timer
            statsTimer?.invalidate()
            statsTimer = nil
        }
        
        // Update debug info
        updateDebugInfo()
    }
    
    // Update peer table visibility based on available peers
    private func updatePeerTableVisibility() {
        let hasPeers = !webRTCService.availablePeers.isEmpty
        let isJoining = webRTCService.isJoining
        let isConnected = webRTCService.isConnected
        
        peerListTableView.isHidden = !hasPeers || !isJoining || isConnected
        
        // Update status text
        if isJoining && hasPeers && !isConnected {
            statusLabel.text = "Select a host to connect to"
        } else if isJoining && !hasPeers && !isConnected {
            statusLabel.text = "Searching for hosts..."
        }
    }
    
    // Handle receiving remote video track
    private func handleRemoteVideoTrack(_ videoTrack: RTCVideoTrack) {
        print("StreamingVC: Received remote video track")
        
        // Set the track in the video view
        videoView.setVideoTrack(videoTrack)
        
        // Log track details
        print("StreamingVC: Video track ID: \(videoTrack.trackId)")
        print("StreamingVC: Video track enabled: \(videoTrack.isEnabled)")
        
        // Make sure the video view is visible
        videoView.isHidden = false
        
        // Update UI state
        loadingIndicator.stopAnimating()
        statusLabel.isHidden = true
        peerListTableView.isHidden = true
        
        // Set hasReceivedFrames to true after a short delay to verify frames are actually coming through
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.videoTrackCheck()
        }
        
        // Request a key frame to kickstart the video
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Simulate enabling/disabling to trigger a keyframe
            videoTrack.isEnabled = false
            videoTrack.isEnabled = true
            print("StreamingVC: Requested keyframe by toggling track")
            
            // Request another keyframe after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                videoTrack.isEnabled = false
                videoTrack.isEnabled = true
                print("StreamingVC: Requested second keyframe")
            }
        }
    }
    
    // Track if we're receiving frames
    private func videoTrackCheck() {
        webRTCService.getStats { [weak self] stats in
            guard let self = self else { return }
            
            var totalFramesDecoded: Int32 = 0
            
            // Look for frames decoded stat
            stats.statistics.forEach { (statsId, statsObj) in
                if statsObj.type == "inbound-rtp" && statsObj.values["mediaType"] as? String == "video" {
                    if let framesDecoded = statsObj.values["framesDecoded"] as? Int32 {
                        totalFramesDecoded = framesDecoded
                    }
                }
            }
            
            // Update our tracking variables
            DispatchQueue.main.async {
                self.framesReceivedCount = totalFramesDecoded
                
                // Check if we've received any frames
                self.hasReceivedFrames = totalFramesDecoded > 0
                
                // Update debug info
                self.updateDebugInfo()
            }
        }
    }
    
    // Show error message
    private func showError(_ message: String) {
        statusLabel.text = message
        statusLabel.isHidden = false
        loadingIndicator.stopAnimating()
        
        // Flash the background red briefly
        UIView.animate(withDuration: 0.3, animations: {
            self.statusLabel.backgroundColor = UIColor.red.withAlphaComponent(0.6)
        }) { _ in
            UIView.animate(withDuration: 0.3) {
                self.statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            }
        }
    }
    
    // Handle back button tap
    @objc private func handleBackButton() {
        // Disconnect from WebRTC session
        webRTCService.disconnect()
        
        // Call disconnect handler
        onDisconnect?()
        
        // Dismiss view controller
        dismiss(animated: true)
    }
    
    // Handle quality button tap
    @objc private func handleQualityButton() {
        let alert = UIAlertController(title: "Video Quality", message: "Select streaming quality", preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "High Quality", style: .default) { [weak self] _ in
            self?.webRTCService.setVideoQuality(.high)
        })
        
        alert.addAction(UIAlertAction(title: "Medium Quality", style: .default) { [weak self] _ in
            self?.webRTCService.setVideoQuality(.medium)
        })
        
        alert.addAction(UIAlertAction(title: "Low Quality", style: .default) { [weak self] _ in
            self?.webRTCService.setVideoQuality(.low)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let popoverController = alert.popoverPresentationController {
            popoverController.sourceView = qualityButton
            popoverController.sourceRect = qualityButton.bounds
        }
        
        present(alert, animated: true)
    }
    
    // Start stats timer
    private func startStatsTimer() {
        statsTimer?.invalidate()
        
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
            self?.videoTrackCheck()
        }
        
        // Initial stats update
        updateStats()
    }
    
    // Update connection statistics
    private func updateStats() {
        webRTCService.getStats { [weak self] stats in
            guard let self = self else { return }
            
            var statsText = ""
            
            // Process statistics using the new API
            stats.statistics.forEach { (statsId, statsObject) in
                // Handle inbound video RTP statistics
                if statsObject.type == "inbound-rtp" {
                    if statsObject.values["mediaType"] as? String == "video" {
                        if let bytesReceived = statsObject.values["bytesReceived"] as? Int64 {
                            statsText += "Received: \(self.formatBytes(String(bytesReceived)))\n"
                        }
                        
                        if let packetsLost = statsObject.values["packetsLost"] as? Int32 {
                            statsText += "Packets Lost: \(packetsLost)\n"
                        }
                        
                        if let frameWidth = statsObject.values["frameWidth"] as? Int32,
                           let frameHeight = statsObject.values["frameHeight"] as? Int32 {
                            statsText += "Resolution: \(frameWidth)×\(frameHeight)\n"
                            
                            // Update video view aspect ratio
                            DispatchQueue.main.async {
                                self.videoView.updateAspectRatio(width: CGFloat(frameWidth), height: CGFloat(frameHeight))
                            }
                        }
                        
                        if let framesDecoded = statsObject.values["framesDecoded"] as? Int32,
                           let timestamp = statsObject.values["timestamp"] as? Double,
                           let timeStampOffset = self.statsTimeReference?.timeIntervalSince1970 {
                            let timeSeconds = (timestamp / 1000) - timeStampOffset
                            if timeSeconds > 0, let lastFramesDecoded = self.lastFramesDecoded {
                                let fps = Int((Double(framesDecoded - lastFramesDecoded) / timeSeconds).rounded())
                                statsText += "FPS: \(fps)\n"
                            }
                            self.lastFramesDecoded = framesDecoded
                            self.statsTimeReference = Date()
                            
                            // Update frames received count
                            self.framesReceivedCount = framesDecoded
                            
                            // Check if we've received frames and notify
                            if framesDecoded > 0 && !self.hasReceivedFrames {
                                self.hasReceivedFrames = true
                            }
                        }
                        
                        if let jitterBuffer = statsObject.values["jitterBufferDelay"] as? Double,
                           let jitterSamples = statsObject.values["jitterBufferEmittedCount"] as? Int64,
                           jitterSamples > 0 {
                            let jitterMs = Int((jitterBuffer / Double(jitterSamples)) * 1000)
                            statsText += "Jitter: \(jitterMs)ms\n"
                        }
                        
                        if let decodeTime = statsObject.values["totalDecodeTime"] as? Double,
                           let framesDecoded = statsObject.values["framesDecoded"] as? Int32,
                           framesDecoded > 0 {
                            let avgDecodeMs = Int((decodeTime / Double(framesDecoded)) * 1000)
                            statsText += "Decode: \(avgDecodeMs)ms\n"
                        }
                    }
                }
                // Get candidate pair RTT
                else if statsObject.type == "candidate-pair" && statsObject.values["nominated"] as? Bool == true {
                    if let rtt = statsObject.values["currentRoundTripTime"] as? Double {
                        let rttMs = Int(rtt * 1000)
                        statsText += "RTT: \(rttMs)ms\n"
                    }
                }
            }
            
            // Update stats label on main thread
            DispatchQueue.main.async {
                self.statsLabel.text = statsText
                self.updateStatsVisibility(!statsText.isEmpty)
                
                // Update debug info
                self.updateDebugInfo()
            }
        }
    }
    
    // Update stats visibility
    private func updateStatsVisibility(_ visible: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.statsView.isHidden = !visible
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

// MARK: - UITableViewDelegate, UITableViewDataSource
extension StreamingViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return webRTCService.availablePeers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell", for: indexPath)
        
        // Configure cell
        let peer = webRTCService.availablePeers[indexPath.row]
        
        cell.textLabel?.text = peer.displayName
        cell.textLabel?.textColor = .white
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        
        // Add device icon
        let deviceIcon = UIImage(systemName: "iphone")?.withTintColor(.white, renderingMode: .alwaysTemplate)
        cell.imageView?.image = deviceIcon
        cell.imageView?.tintColor = .white
        
        // Add disclosure indicator
        cell.accessoryType = .disclosureIndicator
        cell.tintColor = .white
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Connect to selected peer
        let peer = webRTCService.availablePeers[indexPath.row]
        webRTCService.connectToPeer(peer)
        
        // Update UI
        statusLabel.text = "Connecting to \(peer.displayName)..."
        loadingIndicator.startAnimating()
        peerListTableView.isHidden = true
    }
}
