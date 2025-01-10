import SwiftUI

struct CaptureQualityOverlay: View {
    let metrics: CaptureQualityMetrics
    let qualityStatus: CaptureQualityStatus
    
    var body: some View {
        VStack(spacing: 8) {
            // Primary Status Message
            Text(statusMessage)
                .font(.headline)
                .foregroundColor(.white)
            
            // Quality Indicators
            HStack(spacing: 20) {
                QualityIndicator(
                    icon: "camera.metering.center.weighted",
                    value: metrics.depthQuality,
                    label: "Depth"
                )
                
                QualityIndicator(
                    icon: "hand.raised.slash",
                    value: metrics.motionSteadiness,
                    label: "Stability"
                )
                
                QualityIndicator(
                    icon: "square.on.square",
                    value: metrics.surfaceCoverage,
                    label: "Coverage"
                )
            }
            
            // Warning Message if needed
            if case .limited(let reason) = qualityStatus {
                Text(warningMessage(for: reason))
                    .font(.subheadline)
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .padding(.top, 40)
    }
    
    private var statusMessage: String {
        switch qualityStatus {
        case .excellent:
            return "Excellent Capture Quality"
        case .good:
            return "Continue Scanning"
        case .limited:
            return "Improve Scan Quality"
        case .notAvailable:
            return "Cannot Capture"
        }
    }
    
    private func warningMessage(for reason: CaptureQualityStatus.LimitedReason) -> String {
        switch reason {
        case .poorDepth:
            return "Move closer to surface"
        case .excessiveMotion:
            return "Move more slowly"
        case .insufficientFeatures:
            return "Surface needs more detail"
        case .lowLight:
            return "Increase lighting"
        }
    }
}

struct QualityIndicator: View {
    let icon: String
    let value: Float
    let label: String
    
    private var color: Color {
        switch value {
        case ..<0.3:
            return .red
        case 0.3..<0.7:
            return .yellow
        default:
            return .green
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            
            ProgressBar(progress: value)
                .frame(width: 32, height: 3)
                .animation(.easeInOut, value: value)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.white)
        }
    }
}

struct ProgressBar: View {
    let progress: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
        }
    }
}

#if DEBUG
struct CaptureQualityOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            
            CaptureQualityOverlay(
                metrics: CaptureQualityMetrics(
                    isDepthAvailable: true,
                    depthQuality: 0.8,
                    motionSteadiness: 0.6,
                    surfaceCoverage: 0.4
                ),
                qualityStatus: .limited(reason: .excessiveMotion)
            )
        }
    }
}
#endif
