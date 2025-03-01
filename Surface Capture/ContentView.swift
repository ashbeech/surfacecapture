//
//  ContentView.swift
//  Surface Capture App
//

import RealityKit
import SwiftUI
import os

@available(iOS 17.0, *)
struct ContentView: View {
    static let logger = Logger(subsystem: "com.example.SurfaceCapture",
                               category: "ContentView")
    
    @StateObject var appModel: AppDataModel = AppDataModel.instance
    @State private var capturedModelURL: URL?
    @State private var showReconstructionView: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var sessionInitializing: Bool = false
    
    private var showProgressView: Bool {
        appModel.state == .completed || appModel.state == .restart || appModel.state == .ready
    }
    
    var body: some View {
        ZStack {
            // If in image plane mode and we have a selected image, show the AR view
            if appModel.captureType == .imagePlane && appModel.isImagePlacementMode {
                // Show the image plane AR view
                ARSceneView(capturedModelURL: nil, arController: ARPlaneCaptureViewController(mode: .imagePlane, entity: appModel.selectedModelEntity))
                    .environmentObject(appModel)
                    .edgesIgnoringSafeArea(.all)
            } else if let modelURL = capturedModelURL {
                ModelView(modelFile: modelURL) {
                    capturedModelURL = nil
                    appModel.state = .ready
                }
                .edgesIgnoringSafeArea(.all)
            } else if appModel.state == .capturing {
                if let session = appModel.objectCaptureSession, !sessionInitializing {
                    // Only show the CapturePrimaryView when session is ready
                    CapturePrimaryView(session: session)
                        .environmentObject(appModel)
                } else {
                   /*
                    // Show a loading view while session initializes
                    VStack {
                        CircularProgressView()
                        Text("Initializing camera...")
                            .font(.headline)
                            .padding()
                    }
                    */
                }
            } else if appModel.state == .reconstructing || appModel.state == .prepareToReconstruct {
                // Show progress view during reconstruction
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 30) {
                        ProcessingProgressView(progress: appModel.reconstructionProgress)
                        
                        if appModel.reconstructionProgress == 0 {
                            Text("Preparing to process...")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else if showProgressView {
                CircularProgressView()
            }
        }
        .onChange(of: appModel.state) { _, newState in
            ContentView.logger.debug("State changed to: \(newState)")
            
            if newState == .capturing {
                // When transitioning to capturing state, set initializing to true briefly
                // to ensure the session is properly set up before showing the capture view
                /*
                sessionInitializing = true
                
                // Check session state after a short delay to let initialization complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let session = appModel.objectCaptureSession {
                        if case .failed = session.state {
                            showErrorAlert = true
                        } else {
                            sessionInitializing = false
                        }
                    } else {
                        // No session available
                        showErrorAlert = true
                    }
                }*/
            } else if newState == .failed {
                showErrorAlert = true
                showReconstructionView = false
                
            } else if newState == .viewing {
                if appModel.captureType == .objectCapture {
                    // Only show reconstruction view for object capture
                    showReconstructionView = true
                }
                // For image mode, no need to do anything special - the ZStack condition will handle it
            } else if newState == .restart {
                // Clear everything and go back to capture
                print("***** CLEAR EVERYTHING *****")
                
                capturedModelURL = nil
                showReconstructionView = false
                sessionInitializing = false
                appModel.state = .ready
            }
        }
        .sheet(isPresented: $showReconstructionView) {
            if let folderManager = appModel.scanFolderManager {
                let outputFile = folderManager.modelsFolder.appendingPathComponent("model-mobile.usdz")
                ModelView(modelFile: outputFile) {
                    capturedModelURL = outputFile
                }
            }
        }
        .alert(
            "Failed: " + (appModel.error != nil ? "\(String(describing: appModel.error!))" : ""),
            isPresented: $showErrorAlert,
            actions: {
                Button("OK") {
                    ContentView.logger.log("Calling restart...")
                    appModel.state = .restart
                }
            },
            message: {}
        )
        .environmentObject(appModel)
    }
}

/*
 // Create the ARImagePlaneView for displaying the image in AR
 @available(iOS 17.0, *)
 struct ARImagePlaneView: UIViewControllerRepresentable {
 @EnvironmentObject var appModel: AppDataModel
 
 func makeUIViewController(context: Context) -> ARPlaneCaptureViewController {
 ContentView.logger.debug("Creating ARPlaneCaptureViewController for image plane mode")
 
 // Create controller with the proper mode and entity
 let controller = ARPlaneCaptureViewController(
 mode: .imagePlane,
 entity: appModel.selectedModelEntity
 )
 
 appModel.arViewController = controller
 
 return controller
 }
 
 func updateUIViewController(_ uiViewController: ARPlaneCaptureViewController, context: Context) {
 // Update if the image changes
 if let selectedImage = appModel.selectedImage,
 let entity = appModel.selectedModelEntity {
 
 ImagePlaneEntity.updateTexture(entity, with: selectedImage)
 }
 }
 
 static func dismantleUIViewController(_ uiViewController: ARPlaneCaptureViewController, coordinator: ()) {
 uiViewController.pauseARSession()
 }
 }
 */

private struct CircularProgressView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .light ? .black : .white))
                Spacer()
            }
            Spacer()
        }
    }
}

struct ProcessingProgressView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Processing Surface Capture")
                .font(.headline)
            
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    // Background of progress bar
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 20)
                    
                    // Foreground of progress bar
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue)
                        .frame(width: max(0, min(geometry.size.width * CGFloat(progress), geometry.size.width)), height: 20)
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            
            Text("\(Int(progress * 100))%")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(15)
        .shadow(radius: 5)
        .padding(.horizontal, 40)
    }
}
#if DEBUG
@available(iOS 17.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
