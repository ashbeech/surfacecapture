//
//  ReconstructionView.swift
//  Surface Capture
//

import SwiftUI
import os

struct ReconstructionView: View {
    static let logger = Logger(subsystem: "com.example.SurfaceCapture", category: "ReconstructionView")
    
    @EnvironmentObject var appModel: AppDataModel
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Top Navigation - Title and Back button with safe area handling
                HStack {
                    // Back Button
                    Button(action: {
                        // Reset everything and go back to capture state
                        appModel.photogrammetrySession?.cancel() // Cancel ongoing processing
                        
                        // This is critical - we need to reset the image plane mode flags
                        appModel.isImagePlacementMode = false
                        appModel.selectedImage = nil
                        appModel.selectedModelEntity = nil
                        appModel.captureType = .objectCapture // Reset to object capture mode
                        
                        // Then reset the state to restart like we do in object capture mode
                        appModel.state = .restart
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                    }
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                    .padding(.leading, 20)
                    
                    Spacer()
                    
                    // Title
                    Text("Processing Scan")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    
                    Spacer()
                    
                    // Empty view for balance
                    Color.clear
                        .frame(width: 40, height: 40)
                        .padding(.trailing, 20)
                }
                .padding(.top, 60) // To clear status bar
                
                Spacer()
                
                // Processing indicator and progress
                VStack(spacing: 20) {
                    // Progress circle
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 8)
                            .opacity(0.3)
                            .foregroundColor(.gray)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(appModel.reconstructionProgress))
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                            .foregroundColor(.blue)
                            .rotationEffect(Angle(degrees: 270.0))
                            .animation(.linear, value: appModel.reconstructionProgress)
                        
                        Text("\(Int(appModel.reconstructionProgress * 100))%")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)
                    }
                    .frame(width: 150, height: 150)
                    
                    Text("Creating 3D model...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("This may take several minutes. Please don't close the app.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(15)
                
                Spacer()
                
                // Information text at bottom
                Text("Processing performance depends on your device model and scan complexity.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
            .edgesIgnoringSafeArea(.top)
        }
        .onAppear {
            ReconstructionView.logger.debug("Reconstruction view appeared")
        }
    }
}
