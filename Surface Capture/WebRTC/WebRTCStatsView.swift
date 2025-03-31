//
//  WebRTCStatsView.swift
//  CameraStreamer
//
//  Created by Ashley Davison on 29/03/2025.
//

import SwiftUI
import WebRTC

struct WebRTCStatsView: View {
    @ObservedObject var statsModel: WebRTCStatsModel
    
    var body: some View {
        VStack {
            // Performance graph
            if !statsModel.performanceHistory.isEmpty {
                performanceGraph
            }
            
            // Stats helper component
            statsHelper
                .padding(.top, 10)
        }
    }
    
    var statsHelper: some View {
        VStack {
            // Stats summary panel
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    // FPS indicator with color coding
                    HStack {
                        Image(systemName: "gauge")
                            .foregroundColor(.white)
                        Text("FPS:")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                        Text(String(format: "%.1f", statsModel.fps))
                            .foregroundColor(fpsColor)
                            .font(.system(size: 14, weight: .bold))
                    }
                    
                    // Bitrate indicator
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.white)
                        Text("Bitrate:")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                        Text(formatBitrate(statsModel.bitrate))
                            .foregroundColor(bitrateColor)
                            .font(.system(size: 14, weight: .bold))
                    }
                    
                    // Latency indicator
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.white)
                        Text("Latency:")
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .medium))
                        Text(String(format: "%.0f ms", statsModel.latency))
                            .foregroundColor(latencyColor)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                
                Spacer()
                
                // Toggle for detailed stats view
                Button(action: {
                    withAnimation {
                        statsModel.showDetailedStats.toggle()
                    }
                }) {
                    VStack {
                        Image(systemName: statsModel.showDetailedStats ? "chevron.down" : "chevron.right")
                            .foregroundColor(.white)
                        Text(statsModel.showDetailedStats ? "Less" : "More")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.5))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Detailed stats view (conditional)
            if statsModel.showDetailedStats {
                ScrollView {
                    Text(statsModel.detailedStatsText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 200)
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    var performanceGraph: some View {
        VStack(alignment: .leading) {
            Text(graphTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.leading)
            
            // Graph selector
            Picker("Graph Type", selection: $statsModel.selectedGraphType) {
                Text("FPS").tag(StatsGraphType.fps)
                Text("Bitrate").tag(StatsGraphType.bitrate)
                Text("Latency").tag(StatsGraphType.latency)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Graph view
            GeometryReader { geometry in
                ZStack {
                    // Graph background
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                    
                    // Grid lines
                    ForEach(0..<5) { i in
                        Path { path in
                            let y = geometry.size.height * CGFloat(i) / 4
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    }
                    
                    // Data points
                    Path { path in
                        guard !statsModel.performanceHistory.isEmpty else { return }
                        
                        let points = statsModel.performanceHistory.enumerated().map { (index, dataPoint) -> CGPoint in
                            let x = geometry.size.width * CGFloat(index) / CGFloat(statsModel.performanceHistory.count - 1)
                            let value: Double
                            
                            switch statsModel.selectedGraphType {
                            case .fps:
                                value = min(dataPoint.fps, 30) // Cap at 30 FPS for graph
                                let normalizedY = value / 30.0 // Normalize to 0-1 range
                                let y = geometry.size.height * (1 - CGFloat(normalizedY))
                                return CGPoint(x: x, y: y)
                            case .bitrate:
                                value = min(dataPoint.bitrate, 8000) // Cap at 8 Mbps
                                let normalizedY = value / 8000.0
                                let y = geometry.size.height * (1 - CGFloat(normalizedY))
                                return CGPoint(x: x, y: y)
                            case .latency:
                                value = min(dataPoint.latency, 500) // Cap at 500ms
                                let normalizedY = value / 500.0
                                let y = geometry.size.height * (1 - CGFloat(normalizedY))
                                return CGPoint(x: x, y: y)
                            }
                        }
                        
                        if let firstPoint = points.first {
                            path.move(to: firstPoint)
                        }
                        
                        for index in 1..<points.count {
                            path.addLine(to: points[index])
                        }
                    }
                    .stroke(graphColor, lineWidth: 2)
                }
            }
            .frame(height: 120)
            .cornerRadius(8)
            .padding(.horizontal)
            
            // Axis labels
            HStack {
                Text(minLabel)
                Spacer()
                Text(maxLabel)
            }
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    // Helper computed properties for color coding the metrics
    private var fpsColor: Color {
        if statsModel.fps >= 20 {
            return .green
        } else if statsModel.fps >= 15 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private var bitrateColor: Color {
        if statsModel.bitrate >= 2000 { // 2 Mbps or higher for 4K
            return .green
        } else if statsModel.bitrate >= 1000 { // 1 Mbps is acceptable
            return .yellow
        } else {
            return .red
        }
    }
    
    private var latencyColor: Color {
        if statsModel.latency <= 100 { // Under 100ms is good
            return .green
        } else if statsModel.latency <= 300 { // Under 300ms is acceptable
            return .yellow
        } else {
            return .red
        }
    }
    
    private var graphTitle: String {
        switch statsModel.selectedGraphType {
        case .fps:
            return "Frames Per Second"
        case .bitrate:
            return "Bandwidth (Kbps)"
        case .latency:
            return "Latency (ms)"
        }
    }
    
    private var minLabel: String {
        return "0"
    }
    
    private var maxLabel: String {
        switch statsModel.selectedGraphType {
        case .fps:
            return "30 FPS"
        case .bitrate:
            return "8 Mbps"
        case .latency:
            return "500 ms"
        }
    }
    
    private var graphColor: Color {
        switch statsModel.selectedGraphType {
        case .fps:
            return .blue
        case .bitrate:
            return .green
        case .latency:
            return .orange
        }
    }
    
    // Helper function to format bitrate
    private func formatBitrate(_ kbps: Double) -> String {
        if kbps >= 1000 {
            return String(format: "%.2f Mbps", kbps / 1000)
        } else {
            return String(format: "%.0f Kbps", kbps)
        }
    }
}
