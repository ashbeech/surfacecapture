//
//  ModelView.swift
//  Surface Capture App
//

import SwiftUI
import QuickLook
import ARKit
import os

struct ModelView: View {
    static let logger = Logger(subsystem: "com.example.SurfaceCapture", category: "ModelView")
    
    let modelFile: URL
    var onDismiss: (() -> Void)? = nil
    
    @Environment(\.presentationMode) private var presentationMode
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showARView = false
    @StateObject private var arController = ARPlaneCaptureViewController(mode: .objectCapture)

    var body: some View {
        ZStack {
            if !showError {
                // Model Preview
                ModelPreviewController(modelFile: modelFile) {
                    // No-op dismiss callback - using presentation mode instead
                }
                
                // Add CTA Button at the bottom
                VStack {
                    Spacer()
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
            } else {
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
        .navigationBarItems(leading:
            Button(action: { dismiss() }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
        )
        .onAppear {
            verifyAndShowModel()
        }
    }
    
    private func dismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func verifyAndShowModel() {
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
