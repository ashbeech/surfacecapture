//
//  ModelView.swift
//  Surface Capture App
//

import SwiftUI
import QuickLook
import ARKit
import os
// In ModelView.swift
struct ModelView: View {
    static let logger = Logger(subsystem: "com.example.SurfaceCapture", category: "ModelView")
    
    let modelFile: URL
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.presentationMode) private var presentationMode
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showARView = false
    @StateObject private var arController = ARPlaneCaptureViewController(mode: .objectCapture)
    @EnvironmentObject var appModel: AppDataModel // Add this to access app model

    var body: some View {
        ZStack {
            if !showError {
                // Model Preview
                ModelPreviewController(modelFile: modelFile) {
                    // No-op dismiss callback - using presentation mode instead
                }
                
                // Add Title and Back Button at the top
                VStack {
                    // Title and Back button with safe area handling
                    HStack {
                        // Back Button
                        Button(action: {
                            // Reset everything and go back to capture state
                            arController.clearARScene()
                            
                            // This is critical - we need to reset the image plane mode flags
                            appModel.isImagePlacementMode = false
                            appModel.selectedImage = nil
                            appModel.selectedModelEntity = nil
                            appModel.captureType = .objectCapture // Reset to object capture mode
                            
                            // Then reset the state to restart like we do in object capture mode
                            appModel.state = .restart
                            
                            dismiss()
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
                        Text("Scan Preview")
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
                    
                    // Keep existing bottom CTA Button
                    Button(action: {
                        showARView = true
                    }) {
                        HStack {
                            Image(systemName: "cube.transparent")
                            Text("Add to AR Scene")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding(.bottom, 40)
                }
                .edgesIgnoringSafeArea(.top)
            } else {
                // Keep existing error view
                VStack(spacing: 20) {
                    Text("Error Loading Model")
                        .font(.headline)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 16) {
                        Button("Try Again") {
                            verifyAndShowModel()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Back") {
                            dismiss()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 5)
                .padding()
            }
        }
        .fullScreenCover(isPresented: $showARView) {
            ARSceneView(capturedModelURL: modelFile, arController: arController)
                .environmentObject(AppDataModel.instance)
                .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            verifyAndShowModel()
        }
    }
    
    // Keep existing methods
    private func dismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func verifyAndShowModel() {
        // Keep existing implementation
        showError = false
        
        if !FileManager.default.fileExists(atPath: modelFile.path) {
            ModelView.logger.error("Model file not found at path: \(modelFile.path)")
            showError = true
            errorMessage = "Model file not found. Please try capturing again."
            return
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelFile.path)
            if let size = attributes[.size] as? UInt64, size == 0 {
                ModelView.logger.error("Model file is empty")
                showError = true
                errorMessage = "Model file is empty. Please try capturing again."
                return
            }
            
            let _ = try Data(contentsOf: modelFile)
        } catch {
            ModelView.logger.error("Error reading model file: \(error)")
            showError = true
            errorMessage = "Error reading model file. Please try capturing again."
            return
        }
    }
}

struct ModelPreviewController: UIViewControllerRepresentable {
    let modelFile: URL
    let dismissCallback: () -> Void

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: ModelPreviewController

        init(_ parent: ModelPreviewController) {
            self.parent = parent
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.modelFile as QLPreviewItem
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            parent.dismissCallback()
        }
    }
}
