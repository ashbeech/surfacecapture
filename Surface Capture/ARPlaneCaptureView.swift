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
    @State private var isHostingStream = false
    
    // Add state to track if we need to resume AR after dismissal
    @State private var needsARResume = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Only show AR view when not streaming
            if !isJoiningStream && !isHostingStream {
                ARPlaneCaptureView(
                    capturedModelURL: capturedModelURL,
                    viewController: arController
                )
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    print("ARSceneView appeared")
                    // Explicitly disable any coaching overlays
                    arController.removeCoachingOverlay()
                    
                    // Resume AR if we're returning from streaming
                    if needsARResume {
                        needsARResume = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            arController.resumeARSession()
                        }
                    }
                }
            }
            
            // Top Navigation Buttons
            VStack {
                HStack {
                    // Back Button - Different action depending on mode
                    Button(action: {
                        if isJoiningStream || isHostingStream {
                            // If we're streaming, stop streaming and go back to AR view
                            handleReturnFromStreaming()
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
                    } else if isHostingStream {
                        Text("Hosting Stream")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.7))
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
                        
                        // Host button in work mode (renamed from streaming)
                        Button(action: {
                            startHostingStream()
                        }) {
                            Image(systemName: "wifi")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                        }
                        .background(Color.blue.opacity(0.7))
                        .clipShape(Circle())
                        .padding(.trailing, 20)
                    } else {
                        // Standard mode controls
                        HStack {
                            // Join button in standard mode
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
            
            // Main UI overlay with ZStack to properly layer controls
            ZStack {
                // Main content container
                VStack {
                    Spacer()
                    
                    if !isJoiningStream && !isHostingStream {
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
                            } else {
                                // Normal Mode Controls - always show these in the same position
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
                                    
                                    // Rotation Lock
                                    Button(action: {
                                        arController.lockedRotation.toggle()
                                    }) {
                                        Image(systemName: arController.lockedRotation ? "rotate.left.fill" : "rotate.left")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                    }
                                    .background(arController.lockedRotation ? Color.red.opacity(0.7) : Color.black.opacity(0.7))
                                    .clipShape(Circle())
                                    
                                    // Scale Lock
                                    Button(action: {
                                        arController.lockedScale.toggle()
                                    }) {
                                        Image(systemName: arController.lockedScale ? "arrow.up.and.down.circle.fill" : "arrow.up.and.down.circle")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                    }
                                    .background(arController.lockedScale ? Color.red.opacity(0.7) : Color.black.opacity(0.7))
                                    .clipShape(Circle())
                                    
                                    // Position Lock
                                    Button(action: {
                                        arController.lockedPosition.toggle()
                                    }) {
                                        Image(systemName: arController.lockedPosition ? "lock.fill" : "lock.open")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .frame(width: 40, height: 40)
                                    }
                                    .background(arController.lockedPosition ? Color.red.opacity(0.7) : Color.black.opacity(0.7))
                                    .clipShape(Circle())
                                }
                                .padding(.bottom, 20)
                                .zIndex(1) // Ensure these stay on top
                            }
                        }
                    }
                }
                
                // Model Controls when selected - show on sides without affecting bottom controls
                if arController.isModelSelected && !arController.isWorkModeActive && arController.isModelPlaced {
                    HStack {
                        // Left side controls column
                        VStack(spacing: 15) {
                            // Auto-align button
                            Button(action: {
                                arController.autoAlignModelWithSurface()
                            }) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            
                            // X-axis rotation toggle
                            Button(action: {
                                arController.toggleRotationX()
                            }) {
                                Image(systemName: "rotate.3d.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(arController.isRotatingX ? .yellow : .white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .overlay(
                                        Text("X")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .offset(x: 12, y: 12)
                                    )
                            }
                            
                            // Y-axis rotation toggle
                            Button(action: {
                                arController.toggleRotationY()
                            }) {
                                Image(systemName: "rotate.3d.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(arController.isRotatingY ? .yellow : .white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .overlay(
                                        Text("Y")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .offset(x: 12, y: 12)
                                    )
                            }
                            
                            // Z-axis rotation toggle
                            Button(action: {
                                arController.toggleRotationZ()
                            }) {
                                Image(systemName: "rotate.3d.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(arController.isRotatingZ ? .yellow : .white)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                    .overlay(
                                        Text("Z")
                                            .font(.caption2)
                                            .foregroundColor(.white)
                                            .offset(x: 12, y: 12)
                                    )
                            }
                        }
                        .padding(.leading, 20)
                        
                        Spacer()
                        
                        // Right side controls column
                        VStack(spacing: 15) {
                            // Close button
                            Button(action: {
                                arController.isModelSelected = false
                                arController.updateModelHighlight(isSelected: false)
                                arController.modelManipulator.endManipulation()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            
                            Spacer()
                                .frame(height: 20)
                            
                            // Opacity increase button
                            Button(action: {
                                arController.increaseOpacity()
                            }) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            
                            // Opacity decrease button
                            Button(action: {
                                arController.decreaseOpacity()
                            }) {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            
                            Spacer()
                                .frame(height: 20)
                            
                            
                             // Undo button
                             Button(action: {
                                 arController.undoTransformation()
                             }) {
                                 Image(systemName: "arrow.uturn.backward")
                                     .font(.system(size: 20))
                                     .foregroundColor(.white)
                                     .frame(width: 40, height: 40)
                             }
                             .background(arController.canUndo ? Color.blue.opacity(0.7) : Color.gray.opacity(0.7))
                             .clipShape(Circle())
                             .disabled(!arController.canUndo)
                             .opacity(arController.canUndo ? 1.0 : 0.6)
                             
                             // Redo button
                             Button(action: {
                                 arController.redoTransformation()
                             }) {
                                 Image(systemName: "arrow.uturn.forward")
                                     .font(.system(size: 20))
                                     .foregroundColor(.white)
                                     .frame(width: 40, height: 40)
                             }
                             .background(arController.canRedo ? Color.blue.opacity(0.7) : Color.gray.opacity(0.7))
                             .clipShape(Circle())
                             .disabled(!arController.canRedo)
                             .opacity(arController.canRedo ? 1.0 : 0.6)
                            
                            // Reset button
                            Button(action: {
                                arController.resetModelTransforms()
                            }) {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                            
                            Spacer()
                                .frame(height: 20)
                            
                            // Z-depth adjustment
                            Button(action: {
                                arController.toggleDepthAdjustment()
                            }) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 20))
                                    .foregroundColor(arController.isAdjustingDepth ? .yellow : .white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(arController.isAdjustingDepth ? Color.green.opacity(0.7) : Color.black.opacity(0.5))
                            .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                    }
                    // Position the side controls to leave space at the bottom for normal controls
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: arController.isModelSelected)
                }
            }
        }
        .fullScreenCover(isPresented: $isJoiningStream, onDismiss: {
            // This callback is called when the JoinView is dismissed
            // Mark that we need to resume the AR session
            needsARResume = true
        }) {
            // Present the JoinView as a full-screen cover
            JoinView(onClose: {
                // This callback is called when the JoinView's Close button is tapped
                handleReturnFromStreaming()
            })
        }
        .fullScreenCover(isPresented: $isHostingStream, onDismiss: {
            // This callback is called when the HostView is dismissed
            // Mark that we need to resume the AR session
            needsARResume = true
        }) {
            // Present the HostView as a full-screen cover
            HostView(onClose: {
                // This callback is called when the HostView's Close button is tapped
                handleReturnFromStreaming()
            })
        }
        .onChange(of: isJoiningStream) { _, isJoining in
            if !isJoining {
                // We're returning from joining mode
                print("Join mode ended, will resume AR session")
            }
        }
        .onChange(of: isHostingStream) { _, isHosting in
            if !isHosting {
                // We're returning from hosting mode
                print("Host mode ended, will resume AR session")
            }
        }
    }
    
    // Centralized method to handle returning from streaming mode
    private func handleReturnFromStreaming() {
        // First set our streaming state variables to false
        isJoiningStream = false
        isHostingStream = false
        
        // Mark that we need to resume the AR session
        needsARResume = true
        
        // Give the UI time to update before resuming AR
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            arController.resumeARSession()
        }
    }
    
    // Start joining WebRTC stream
    private func startJoiningStream() {
        // End the AR session
        arController.pauseARSession()
        
        // Set state to trigger UI update
        isJoiningStream = true
    }
    
    // Start hosting WebRTC stream
    private func startHostingStream() {
        // Pause AR session to free camera for streaming
        arController.pauseARSession()
        
        // Set state to trigger UI update
        isHostingStream = true
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
