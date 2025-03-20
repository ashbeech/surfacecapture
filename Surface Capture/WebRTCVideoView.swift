//
//  WebRTCVideoView.swift
//  Surface Capture
//

import UIKit
import WebRTC

// UIView that displays video streams from WebRTC
class WebRTCVideoView: UIView {
    // RTCVideoRenderer to display the video
    private var videoRenderer: RTCMTLVideoView
    
    // Constraint references for managing aspect ratio
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var aspectRatio: CGFloat = 9.0/16.0 // Default portrait orientation
    
    // Debug layer to show frame borders
    private var debugLayer: CALayer?
    private var debugLabel: UILabel?
    
    override init(frame: CGRect) {
        // Initialize video renderer
        videoRenderer = RTCMTLVideoView(frame: .zero)
        videoRenderer.videoContentMode = .scaleAspectFill
        
        super.init(frame: frame)
        
        // Set up the video renderer
        setupVideoRenderer()
        
        // Add debugging elements
        #if DEBUG
        setupDebugElements()
        #endif
    }
    
    required init?(coder: NSCoder) {
        // Initialize video renderer
        videoRenderer = RTCMTLVideoView(frame: .zero)
        videoRenderer.videoContentMode = .scaleAspectFill
        
        super.init(coder: coder)
        
        // Set up the video renderer
        setupVideoRenderer()
        
        // Add debugging elements
        #if DEBUG
        setupDebugElements()
        #endif
    }
    
    private func setupVideoRenderer() {
        // Add the video renderer as a subview
        addSubview(videoRenderer)
        
        // Configure video renderer
        videoRenderer.translatesAutoresizingMaskIntoConstraints = false
        
        // Create and activate constraints
        NSLayoutConstraint.activate([
            videoRenderer.centerXAnchor.constraint(equalTo: centerXAnchor),
            videoRenderer.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        // Create constraints for aspect ratio
        widthConstraint = videoRenderer.widthAnchor.constraint(equalTo: widthAnchor)
        heightConstraint = videoRenderer.heightAnchor.constraint(equalTo: heightAnchor)
        
        // Activate constraints
        widthConstraint?.isActive = true
        heightConstraint?.isActive = true
        
        // Set background color
        backgroundColor = .black
    }
    
    #if DEBUG
    private func setupDebugElements() {
        // Debug layer to show frame borders
        debugLayer = CALayer()
        debugLayer?.borderWidth = 2.0
        debugLayer?.borderColor = UIColor.green.cgColor
        
        if let debugLayer = debugLayer {
            layer.addSublayer(debugLayer)
        }
        
        // Debug label to show video status
        debugLabel = UILabel()
        debugLabel?.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        debugLabel?.textColor = .white
        debugLabel?.font = UIFont.systemFont(ofSize: 10)
        debugLabel?.textAlignment = .left
        debugLabel?.numberOfLines = 0
        debugLabel?.text = "Waiting for video..."
        
        if let label = debugLabel {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
                label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8)
            ])
        }
    }
    #endif
    
    private var currentVideoTrack: RTCVideoTrack?
    private var videoFrameCounter: Int = 0
    private var lastFrameCounterReset = Date()
    
    // Set the RTCVideoTrack to display
    func setVideoTrack(_ videoTrack: RTCVideoTrack?) {
        print("VideoView: Setting video track: \(videoTrack?.trackId ?? "nil")")
        
        // Remove any existing tracks
        if let currentTrack = currentVideoTrack {
            print("VideoView: Removing existing track")
            currentTrack.remove(videoRenderer)
            currentVideoTrack = nil
        }
        
        guard let newTrack = videoTrack else {
            print("VideoView: No new track to set")
            #if DEBUG
            updateDebugLabel("No video track available")
            #endif
            return
        }
        
        // Make sure the track is enabled
        newTrack.isEnabled = true
        
        // Store the current track
        currentVideoTrack = newTrack
        
        // Add the renderer to the track - this is critical for video display!
        print("VideoView: Adding renderer to track")
        newTrack.add(videoRenderer)
        
        // Make sure the renderer is visible
        videoRenderer.isHidden = false
        
        // Request layout
        print("VideoView: Requesting layout update")
        setNeedsLayout()
        
        #if DEBUG
        // Start frame counting for debug
        startFrameMonitoring(newTrack)
        #endif
        
        // Request keyframe to kickstart the video
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Simulate enabling/disabling to trigger a keyframe
            newTrack.isEnabled = false
            newTrack.isEnabled = true
            print("VideoView: Requested keyframe by toggling track")
            
            // Request another keyframe after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                newTrack.isEnabled = false
                newTrack.isEnabled = true
                print("VideoView: Requested second keyframe")
            }
        }
    }
    
    #if DEBUG
    private func startFrameMonitoring(_ track: RTCVideoTrack) {
        // Reset counters
        videoFrameCounter = 0
        lastFrameCounterReset = Date()
        
        // Start monitoring frames
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self, let currentTrack = self.currentVideoTrack else {
                timer.invalidate()
                return
            }
            
            // Calculate elapsed time
            let elapsedSeconds = Date().timeIntervalSince(self.lastFrameCounterReset)
            
            // Calculate FPS
            let fps = Double(self.videoFrameCounter) / elapsedSeconds
            
            // Update debug info
            self.updateDebugLabel("Track: \(currentTrack.trackId)\nEnabled: \(currentTrack.isEnabled)\nFrames: \(self.videoFrameCounter)\nFPS: \(String(format: "%.1f", fps))")
            
            // Reset counters every 5 seconds
            if elapsedSeconds > 5.0 {
                self.videoFrameCounter = 0
                self.lastFrameCounterReset = Date()
            }
        }
    }
    
    private func updateDebugLabel(_ text: String) {
        DispatchQueue.main.async {
            self.debugLabel?.text = text
        }
    }
    #endif
    
    // Update aspect ratio based on video dimensions
    func updateAspectRatio(width: CGFloat, height: CGFloat) {
        guard width > 0 && height > 0 else { return }
        
        aspectRatio = height / width
        
        // Update constraints based on new aspect ratio
        updateConstraints()
        
        #if DEBUG
        // Update debug layer frame
        updateDebugLayerFrame()
        #endif
    }
    
    #if DEBUG
    private func updateDebugLayerFrame() {
        DispatchQueue.main.async {
            self.debugLayer?.frame = self.videoRenderer.frame
        }
    }
    #endif
    
    // Update constraints to maintain aspect ratio
    override func updateConstraints() {
        // Get frame dimensions
        let frameWidth = frame.width
        let frameHeight = frame.height
        
        // Calculate video dimensions to maintain aspect ratio while filling the view
        let viewAspectRatio = frameHeight / frameWidth
        
        if aspectRatio > viewAspectRatio {
            // Video is taller than the view, fill width
            widthConstraint?.constant = 0
            heightConstraint?.constant = frameWidth * aspectRatio - frameHeight
        } else {
            // Video is wider than the view, fill height
            heightConstraint?.constant = 0
            widthConstraint?.constant = frameHeight / aspectRatio - frameWidth
        }
        
        super.updateConstraints()
    }
    
    // Handle rotation and size changes
    override func layoutSubviews() {
        super.layoutSubviews()
        
        print("VideoView: Layout updating, frame: \(frame)")
        
        // Update constraints when view size changes
        updateConstraints()
        
        // Make sure the renderer is properly sized
        videoRenderer.frame = bounds
        
        #if DEBUG
        // Update debug layer
        updateDebugLayerFrame()
        #endif
    }
}
