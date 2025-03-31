//
//  WebRTCStatsModel.swift
//  CameraStreamer
//
//  Created by Ashley Davison on 29/03/2025.
//

import Foundation
import WebRTC

// Data model for performance history
struct PerformanceDataPoint: Identifiable {
    var id = UUID()
    var timestamp: Date
    var fps: Double
    var bitrate: Double
    var latency: Double
}

// Graph type enum
enum StatsGraphType {
    case fps, bitrate, latency
}

class WebRTCStatsModel: ObservableObject {
    @Published var statsInfo = "FPS: -- | Bitrate: -- | Latency: -- ms"
    @Published var showDetailedStats = false
    @Published var detailedStatsText = ""
    @Published var fps: Double = 0
    @Published var bitrate: Double = 0
    @Published var latency: Double = 0
    @Published var performanceHistory: [PerformanceDataPoint] = []
    @Published var selectedGraphType: StatsGraphType = .fps
    
    private var statsTimer: Timer?
    private var lastByteCount: Int64 = 0
    private var lastTimestamp: CFTimeInterval = 0
    
    // FPS tracking with rolling average
    private var frameCounter: Int64 = 0
    private var lastFrameCounterReset = CFAbsoluteTimeGetCurrent()
    private var fpsReadings: [Double] = []
    private let fpsWindowSize = 5 // Number of readings to average (adjust as needed)
    
    private let maxHistoryPoints = 600 // Store 10 minutes of data at 1 second intervals
    
    private weak var peerConnection: RTCPeerConnection?
    
    init(peerConnection: RTCPeerConnection?) {
        self.peerConnection = peerConnection
    }
    
    // MARK: - Stats Collection
    
    func setupStatsCollection() {
        // Start collecting stats every second
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectStats()
        }
    }
    
    func stopStatsCollection() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    func setupPeriodicStatsCollection() {
        // Start collecting stats immediately after connection
        collectStats()
    }
    
    func formatBitrate(_ kbps: Double) -> String {
        if kbps >= 1000 {
            return String(format: "%.2f Mbps", kbps / 1000)
        } else {
            return String(format: "%.0f Kbps", kbps)
        }
    }
    
    // Calculate a rolling average for FPS to smooth readings
    private func updateRollingFPS(_ instantFPS: Double) -> Double {
        // Add the new reading
        fpsReadings.append(instantFPS)
        
        // Trim the array if needed
        if fpsReadings.count > fpsWindowSize {
            fpsReadings.removeFirst()
        }
        
        // Calculate average (exclude zeros if we're still building up readings)
        let nonZeroReadings = fpsReadings.filter { $0 > 0 }
        if nonZeroReadings.isEmpty {
            return instantFPS
        }
        
        return nonZeroReadings.reduce(0, +) / Double(nonZeroReadings.count)
    }
    
    // Calculate FPS with accumulated frames
    private var lastFramesDecoded: Int64 = 0
    private var framesAccumulated: [Int64] = []
    private let framesWindowSize = 3 // Number of frame count differences to track
    
    private func calculateSmoothFPS(_ framesDecoded: Int64) -> Double {
        // First call, just store the frames and return 0
        if lastFramesDecoded == 0 {
            lastFramesDecoded = framesDecoded
            return 0
        }
        
        // Calculate frame difference
        let frameDiff = framesDecoded - lastFramesDecoded
        lastFramesDecoded = framesDecoded
        
        // Add to accumulated frames
        framesAccumulated.append(frameDiff)
        if framesAccumulated.count > framesWindowSize {
            framesAccumulated.removeFirst()
        }
        
        // Calculate average frames per interval
        let avgFrames = Double(framesAccumulated.reduce(0, +)) / Double(framesAccumulated.count)
        
        // FPS is average frames divided by time interval (1 second)
        return avgFrames
    }
    
    func collectStats() {
        peerConnection?.statistics { [weak self] report in
            guard let self = self else { return }
            
            // Process video stats
            var currentFps: Double = 0
            var instantFps: Double = 0
            var currentBitrate: Double = 0
            var currentLatency: Double = 0
            var detailedInfo = ""
            
            for (_, stats) in report.statistics {
                // Look for inbound-rtp stats for video
                if stats.type == "inbound-rtp" && (stats.values["kind"] as? String == "video" || stats.values["mediaType"] as? String == "video") {
                    // Extract frames per second
                    if let framesReceived = stats.values["framesReceived"] as? Int64,
                       let framesDecoded = stats.values["framesDecoded"] as? Int64 {
                        
                        // Calculate instantaneous FPS
                        instantFps = Double(self.calculateSmoothFPS(framesDecoded))
                        
                        // Apply rolling average to smooth FPS
                        currentFps = self.updateRollingFPS(instantFps)
                        
                        detailedInfo += "Frames Received: \(framesReceived)\n"
                        detailedInfo += "Frames Decoded: \(framesDecoded)\n"
                        detailedInfo += "Raw FPS: \(String(format: "%.1f", instantFps))\n"
                        detailedInfo += "Smoothed FPS: \(String(format: "%.1f", currentFps))\n\n"
                    }
                    
                    // Extract bytes received for bitrate calculation
                    if let bytesReceived = stats.values["bytesReceived"] as? Int64 {
                        let now = CACurrentMediaTime()
                        if self.lastTimestamp > 0 {
                            let timeDiff = now - self.lastTimestamp
                            let bytesDiff = bytesReceived - self.lastByteCount
                            
                            // Calculate bitrate in Kbps
                            currentBitrate = Double(bytesDiff) * 8.0 / (timeDiff * 1000.0)
                        }
                        
                        self.lastByteCount = bytesReceived
                        self.lastTimestamp = now
                        
                        detailedInfo += "Bytes Received: \(bytesReceived)\n"
                        detailedInfo += "Bitrate: \(self.formatBitrate(currentBitrate))\n\n"
                    }
                    
                    // Extract jitter and RTT for latency estimation
                    if let jitter = stats.values["jitter"] as? Double {
                        detailedInfo += "Jitter: \(String(format: "%.2f ms", jitter * 1000))\n"
                        
                        // Jitter contributes to perceived latency
                        currentLatency += jitter * 1000
                    }
                }
                
                // Look for candidate-pair stats for RTT/latency
                if stats.type == "candidate-pair" && (stats.values["selected"] as? Bool == true) {
                    if let rtt = stats.values["currentRoundTripTime"] as? Double {
                        // RTT in milliseconds
                        let rttMs = rtt * 1000
                        currentLatency = rttMs
                        
                        detailedInfo += "Current RTT: \(String(format: "%.2f ms", rttMs))\n"
                    }
                }
            }
            
            // Update published properties
            DispatchQueue.main.async {
                self.fps = currentFps
                self.bitrate = currentBitrate
                self.latency = currentLatency
                
                // Format the stats info string
                self.statsInfo = "FPS: \(String(format: "%.1f", currentFps)) | "
                    + self.formatBitrate(currentBitrate) + " | "
                    + "Latency: \(String(format: "%.0f", currentLatency)) ms"
                
                self.detailedStatsText = detailedInfo
                
                if self.performanceHistory.isEmpty {
                    // Add initial data point with zeros if no history exists
                    let initialPoint = PerformanceDataPoint(
                        timestamp: Date().addingTimeInterval(-1),
                        fps: 0,
                        bitrate: 0,
                        latency: 0
                    )
                    self.performanceHistory.append(initialPoint)
                }
                
                // Add to history
                let newDataPoint = PerformanceDataPoint(
                    timestamp: Date(),
                    fps: self.fps,
                    bitrate: self.bitrate,
                    latency: self.latency
                )
                
                self.performanceHistory.append(newDataPoint)
                
                // Trim history if needed
                if self.performanceHistory.count > self.maxHistoryPoints {
                    self.performanceHistory.removeFirst(self.performanceHistory.count - self.maxHistoryPoints)
                }
            }
        }
    }
}
