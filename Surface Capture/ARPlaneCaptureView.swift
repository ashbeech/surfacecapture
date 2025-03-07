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
    
    var body: some View {
        ZStack(alignment: .bottom) {
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
            // Top Navigation Buttons - Now with better safe area handling
            VStack {
                HStack {
                    // Back Button - Different action depending on mode
                    Button(action: {
                        if arController.isWorkModeActive {
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
                    
                    // Show mode indicator in work mode
                    if arController.isWorkModeActive {
                        Text("Work Mode")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.7))
                            .cornerRadius(10)
                    }
                    
                    Spacer()
                    
                    // Work Mode / Streaming Button depending on context
                    if arController.isWorkModeActive {
                        // Streaming toggle button in work mode
                        Button(action: {
                            arController.isStreamingActive.toggle()
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
                // Move buttons down enough to clear status bar and provide some spacing
                .padding(.top, 60) // This value works well on most devices
                
                Spacer()
            }
            .edgesIgnoringSafeArea(.top) // Allow content to extend under status bar
            
            // UI Overlays based on current mode
            VStack {
                Spacer()
                
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
                            
                            // Streaming Button
                            Button(action: {
                                arController.isStreamingActive.toggle()
                            }) {
                                Image(systemName: arController.isStreamingActive ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            }
                            .background(arController.isStreamingActive ? Color.blue.opacity(0.7) : Color.black.opacity(0.7))
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
                    }
                }
            }
            
            // Model Controls when selected - only show if not in work mode
            if arController.isModelSelected && !arController.isWorkModeActive {
                HStack {
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
                    
                    // Model manipulation controls (vertically centered)
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
                        
                        // Rotation Controls Group
                        VStack(spacing: 12) {
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
                    }
                    .padding(.trailing, 20)
                    .transition(.move(edge: .trailing))
                    .animation(.easeInOut, value: arController.isModelSelected)
                }
                // Position the control panel in the center vertically
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .onAppear {
            print("ARSceneView appeared")
        }
        .onChange(of: arController.isModelSelected) { oldValue, newValue in
            print("isModelSelected changed from \(oldValue) to \(newValue)")
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
