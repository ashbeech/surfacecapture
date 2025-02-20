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
                        
                        // Top Navigation Buttons
                        VStack {
                            HStack {
                                // Back Button
                                Button(action: {
                                    // Reset everything and go back to capture state
                                    arController.clearARScene()
                                    appModel.state = .restart  // This will trigger a full reset back to capture
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(.leading, 20)
                                .padding(.top, 20)
                                
                                Spacer()
                                
                                // Placeholder Button
                                Button(action: {
                                    // Future functionality
                                }) {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(.trailing, 20)
                                .padding(.top, 20)
                            }
                            Spacer()
                        }
                        
                        // Only show control buttons if model is placed
                        if arController.isModelPlaced {
                            // Pulse Button
                            HStack {
                                Button(action: {
                                    arController.togglePulsing()
                                }) {
                                    Image(systemName: "waveform.path")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(arController.isPulsing ? Color.red : Color.gray)
                                .clipShape(Circle())
                                .padding(.leading, 10)
                            }
                            Spacer()
                            
                            // Lock Controls
                            if !arController.isWorkModeActive {
                                HStack(spacing: 20) {
                                    Spacer()
                                    
                                    Button(action: {
                                        arController.lockedRotation.toggle()
                                    }) {
                                        Image(systemName: arController.lockedRotation ? "rotate.left.fill" : "rotate.left")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .padding(20)
                                    }
                                    .background(arController.lockedRotation ? Color.red : Color.gray)
                                    .clipShape(Circle())
                                    
                                    Button(action: {
                                        arController.lockedScale.toggle()
                                    }) {
                                        Image(systemName: arController.lockedScale ? "arrow.up.and.down.circle.fill" : "arrow.up.and.down.circle")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .padding(20)
                                    }
                                    .background(arController.lockedScale ? Color.red : Color.gray)
                                    .clipShape(Circle())
                                    
                                    Button(action: {
                                        arController.lockedPosition.toggle()
                                    }) {
                                        Image(systemName: arController.lockedPosition ? "lock.fill" : "lock.open")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .padding(20)
                                    }
                                    .background(arController.lockedPosition ? Color.red : Color.gray)
                                    .clipShape(Circle())
                                    
                                    Spacer()
                                }
                                .padding(.bottom, 15)
                            }
                        }
            
            // UI Overlays
            VStack {
                Spacer()
                if !arController.isModelPlaced {
                    // Initial placement instruction
                    Text("Tap on a surface to place the model")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding(.bottom, 20)
                }
                if arController.isModelSelected {
                    // MARK: Model control UI
                    HStack {
                        Spacer()
                        VStack {
                            // Close button
                            Button(action: {
                                arController.isModelSelected = false
                                arController.modelManipulator.endManipulation()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(20)
                            }
                            .background(Color.gray)
                            .clipShape(Circle())
                            
                            // Opacity increase button
                            Button(action: {
                                print("Increase opacity button pressed")
                                arController.increaseOpacity()
                            }) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(20)
                            }
                            .background(Color.gray)
                            .clipShape(Circle())
                            
                            // Opacity decrease button
                            Button(action: {
                                print("Decrease opacity button pressed")
                                arController.decreaseOpacity()
                            }) {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(20)
                            }
                            .background(Color.gray)
                            .clipShape(Circle())
                            
                            // Reset button
                            Button(action: {
                                arController.resetModelTransforms()
                            }) {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(20)
                            }
                            .background(Color.gray)
                            .clipShape(Circle())
                            
                            // Rotation Controls Group
                            VStack(spacing: 10) {
                                // X-axis rotation
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.rotatingX)
                                }) {
                                    Image(systemName: "arrow.up.and.down.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(arController.currentManipulationState == .rotatingX ? Color.green : Color.gray)
                                .clipShape(Circle())
                                
                                // Y-axis rotation
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.rotatingY)
                                }) {
                                    Image(systemName: "arrow.left.and.right.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(arController.currentManipulationState == .rotatingY ? Color.green : Color.gray)
                                .clipShape(Circle())
                                
                                // Z-axis rotation
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.rotatingZ)
                                }) {
                                    Image(systemName: "arrow.clockwise.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(arController.currentManipulationState == .rotatingZ ? Color.green : Color.gray)
                                .clipShape(Circle())
                                
                                // Z-depth adjustment
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.adjustingDepth)
                                }) {
                                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(20)
                                }
                                .background(arController.currentManipulationState == .adjustingDepth ? Color.green : Color.gray)
                                .clipShape(Circle())
                            }
                        }
                        .padding(.bottom, 20)
                        .padding(.trailing, 10)
                        .transition(.move(edge: .trailing))
                        .animation(.easeInOut, value: arController.isModelSelected)
                    }
                }
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
