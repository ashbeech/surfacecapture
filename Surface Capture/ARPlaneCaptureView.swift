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
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ARPlaneCaptureView(
                capturedModelURL: capturedModelURL,
                viewController: arController
            )
            .edgesIgnoringSafeArea(.all)
            
            // UI Overlays
            VStack {
                Spacer()
                if !arController.isModelSelected {
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
                        VStack {
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
                                        .foregroundColor(arController.modelManipulator.currentState == .rotatingX ? .yellow : .white)
                                        .padding(20)
                                }
                                .background(Color.gray)
                                .clipShape(Circle())
                                
                                // Y-axis rotation
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.rotatingY)
                                }) {
                                    Image(systemName: "arrow.left.and.right.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(arController.modelManipulator.currentState == .rotatingY ? .yellow : .white)
                                        .padding(20)
                                }
                                .background(Color.gray)
                                .clipShape(Circle())
                                
                                // Z-axis rotation
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.rotatingZ)
                                }) {
                                    Image(systemName: "arrow.clockwise.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(arController.modelManipulator.currentState == .rotatingZ ? .yellow : .white)
                                        .padding(20)
                                }
                                .background(Color.gray)
                                .clipShape(Circle())
                                
                                // Z-depth adjustment
                                Button(action: {
                                    arController.modelManipulator.startManipulation(.adjustingDepth)
                                }) {
                                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                        .font(.system(size: 24))
                                        .foregroundColor(arController.modelManipulator.currentState == .adjustingDepth ? .yellow : .white)
                                        .padding(20)
                                }
                                .background(Color.gray)
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
