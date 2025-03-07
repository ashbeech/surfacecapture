//
//  StatusMessageView.swift
//  Surface Capture
//
/*
import SwiftUI

/// A consistent message component for displaying status messages
struct StatusMessageView: View {
    let message: String
    let icon: String?
    let type: MessageType
    
    enum MessageType {
        case normal
        case warning
        case error
        case success
    }
    
    init(_ message: String, icon: String? = nil, type: MessageType = .normal) {
        self.message = message
        self.icon = icon
        self.type = type
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
            }
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(10)
    }
    
    private var backgroundColor: Color {
        switch type {
        case .normal:
            return Color.black.opacity(0.7)
        case .warning:
            return Color.orange.opacity(0.7)
        case .error:
            return Color.red.opacity(0.7)
        case .success:
            return Color.green.opacity(0.7)
        }
    }
    
    private var textColor: Color {
        return .white
    }
}

/// An overlay that positions a status message in the top 1/3 of the screen
struct StatusMessageOverlay<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack {
            Spacer().frame(height: UIScreen.main.bounds.height / 6) // Position at roughly 1/3 from top
            content
            Spacer()
        }
    }
}

// Extension to add a simpler init for StatusMessageOverlay with just a message
extension StatusMessageOverlay where Content == StatusMessageView {
    init(_ message: String, icon: String? = nil, type: StatusMessageView.MessageType = .normal) {
        self.init {
            StatusMessageView(message, icon: icon, type: type)
        }
    }
}
*/
