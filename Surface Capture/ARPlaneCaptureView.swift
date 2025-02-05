//
//  ARPlaneCaptureView.swift
//  Surface Capture
//
//  Created by Ashley Davison on 03/01/2025.
//

import SwiftUI
import RealityKit
import ARKit
import Foundation

struct ARPlaneCaptureView: UIViewControllerRepresentable {
    @EnvironmentObject private var appModel: AppDataModel
    let capturedModelURL: URL?
    
    func makeUIViewController(context: Context) -> ARPlaneCaptureViewController {
        let controller = ARPlaneCaptureViewController()
        if let url = capturedModelURL {
            controller.loadCapturedModel(url)
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: ARPlaneCaptureViewController, context: Context) {
        if let url = capturedModelURL {
            uiViewController.loadCapturedModel(url)
        }
    }
}

struct ARSceneView: View {
    @EnvironmentObject private var appModel: AppDataModel
    let capturedModelURL: URL?
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ARPlaneCaptureView(capturedModelURL: capturedModelURL)
                .environmentObject(appModel)  // Add this
                .edgesIgnoringSafeArea(.all)
            
            // UI Overlays
            VStack {
                Spacer()
                /*
                // Debug Text (temporary)
                Text("Model Selected: \(appModel.selectedModelEntity != nil ? "Yes" : "No")")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                
                // Only show controls when model is selected
                if appModel.selectedModelEntity != nil {
                    HStack {
                        Spacer()
                        OpacityControlsView()
                            .environmentObject(appModel)  // Add this
                    }
                }
                 */
                
                // Instructions or other UI elements
                Text("Tap on a surface to place the model")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            print("ARSceneView appeared")
            print("ARSceneView appModel: \(String(describing: appModel))")
            //print("ARSceneView selectedModelEntity: \(String(describing: appModel.selectedModelEntity))")
        }
    }
}
