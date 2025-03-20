//
//  ARPlaneCaptureView.swift
//  Surface Capture
//

import SwiftUI
import RealityKit
import ARKit
import Foundation

struct ARSceneView: View {
    let capturedModelURL: URL?
    @ObservedObject var arController: ARPlaneCaptureViewController
    @EnvironmentObject var appModel: AppDataModel
    
    // Add state to manage streaming session
    @State private var isJoiningStream = false
    @State private var streamingWebRTCService = WebRTCService()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Only show AR view when not streaming
            if !isJoiningStream {
                ARPlaneCaptureView(
                    capturedModelURL: capturedModelURL,
                    viewController: arController
                )
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    print("ARSceneView appeared")
                    // Explicitly disable any coaching overlays
                    arController.removeCoachingOverlay()
                }
            }
            
            // Top Navigation Buttons
            VStack {
                HStack {
                    // Back Button - Different action depending on mode
                    Button(action: {
                        if isJoiningStream {
                            // If we're streaming, stop streaming and go back to AR view
                            stopStreaming()
                        } else if arController.isWorkModeActive {
                            // Exit work mode and return to normal mode
                            arController.isWorkModeActive = false
                            arController.isStreamingActive = false
                        } else {
                            // Reset everything and go back to capture state
                            arController.clearARScene()
                            
                            // This is critical - we need to reset the image plane mode flags
                            appModel.isImagePlacementMode = false
                            appModel.selectedImage = nil
                            appModel.selectedModelEntity = nil
                            appModel.captureType = .objectCapture // Reset to object capture mode
                            
                            // Then reset the state to restart like we do in object capture mode
                            appModel.state = .restart
                        }
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
                    
                    // If we're streaming, show a streaming indicator
                    if isJoiningStream {
                        Text("Viewing Stream")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.7))
                            .cornerRadius(10)
                    }
                    // Work Mode / Streaming Button depending on context
                    else if arController.isWorkModeActive {
                        Text("Work Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(10)
                        
                        // Streaming toggle button in work mode
                        Button(action: {
                            arController.toggleStreamMode()
                        }) {
                            Image(systemName: arController.isStreamingActive ? "wifi" : "wifi.slash")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .background(arController.isStreamingActive ? Color.blue.opacity(0.7) : Color.black.opacity(0.7))
                        .clipShape(Circle())
                        .padding(.trailing, 20)
                    } else {
                        // Standard mode controls
                        HStack {
                            // Stream join button in standard mode
                            Button(action: {
                                startJoiningStream()
                            }) {
                                Image(systemName: "wifi")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.purple.opacity(0.7))
                            .clipShape(Circle())
                            .padding(.trailing, 10)
                            
                            // Work Mode Button in normal mode
                            Button(action: {
                                arController.isWorkModeActive.toggle()
                                // When entering work mode, ensure model isn't selected
                                if arController.isWorkModeActive {
                                    arController.isModelSelected = false
                                    arController.updateModelHighlight(isSelected: false)
                                }
                            }) {
                                Image(systemName: "eye")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            .padding(.trailing, 20)
                        }
                    }
                }
                // Move buttons down enough to clear status bar and provide some spacing
                .padding(.top, 60)
                
                Spacer()
            }
            .edgesIgnoringSafeArea(.top)
            
            // UI Overlays based on current mode
            VStack {
                Spacer()
                
                if !isJoiningStream {
                    if !arController.isModelPlaced {
                        // Initial placement instruction
                        Text("Tap on a surface to place the model")
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                            .padding(.bottom, 20)
                    }
                    
                    // Only show control buttons if model is placed
                    if arController.isModelPlaced {
                        if arController.isWorkModeActive {
                            // Work Mode Controls
                            HStack(spacing: 30) {
                                // Pulse Button
                                Button(action: {
                                    arController.togglePulsing()
                                }) {
                                    Image(systemName: "waveform.path")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)
                                }
                                .background(arController.isPulsing ? Color.green.opacity(0.7) : Color.black.opacity(0.7))
                                .clipShape(Circle())
                            }
                            .padding(.bottom, 20)
                            
                            // Show streaming status if active
                            if arController.isStreamingActive {
                                Text("AR Scene Streaming Active")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.7))
                                    .cornerRadius(10)
                                    .padding(.bottom, 20)
                            }
                        } else {
                            // Normal Mode Controls
                            HStack(spacing: 30) {
                                // Various control buttons...
                                // (control buttons code remains the same)
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            
            // Show streaming view when joining a stream
            if isJoiningStream {
                StreamingView(webRTCService: streamingWebRTCService) {
                    stopStreaming()
                }
                .edgesIgnoringSafeArea(.all)
                .transition(.opacity)
                .animation(.easeInOut, value: isJoiningStream)
            }
        }
        .onDisappear {
            // Clean up any streaming connections when view disappears
            if isJoiningStream {
                stopStreaming()
            }
        }
    }
    
    // Start joining WebRTC stream
    private func startJoiningStream() {
        // Completely end the AR session
        arController.clearARScene()
        
        // Reset the app model state
        if appModel.objectCaptureSession != nil {
            // End the current ObjectCaptureSession
            appModel.objectCaptureSession?.cancel()
            appModel.objectCaptureSession = nil
        }
        
        // Initialize WebRTC service
        streamingWebRTCService = WebRTCService()
        
        // Set state to trigger UI update
        isJoiningStream = true
        
        // Wait a moment for resources to free up, then start joining
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            streamingWebRTCService.startJoining()
        }
    }
    
    // Stop streaming and return to AR view
    private func stopStreaming() {
        // Disconnect WebRTC
        streamingWebRTCService.disconnect()
        
        // Reset state
        isJoiningStream = false
        
        // After a short delay to let resources release, restart in clean state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Restart app in original state
            appModel.state = .restart
        }
    }
}

struct ARPlaneCaptureView: UIViewControllerRepresentable {
    let capturedModelURL: URL?
    let viewController: ARPlaneCaptureViewController
    
    func makeUIViewController(context: Context) -> ARPlaneCaptureViewController {
        if let url = capturedModelURL {
            viewController.loadCapturedModel(url)
        }
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: ARPlaneCaptureViewController, context: Context) {
        if let url = capturedModelURL {
            uiViewController.loadCapturedModel(url)
        }
    }
}
