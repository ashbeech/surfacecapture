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
                .environmentObject(appModel)
                .edgesIgnoringSafeArea(.all)
            } else if appModel.state == .capturing {
                if let session = appModel.objectCaptureSession, !sessionInitializing {
                    // Only show the CapturePrimaryView when session is ready
                    CapturePrimaryView(session: session)
                        .environmentObject(appModel)
                } else {
                    // Show a loading view while session initializes
                    VStack {
                        CircularProgressView()
                        Text("Initializing camera...")
                            .font(.headline)
                            .padding()
                    }
                }
            } else if appModel.state == .reconstructing || appModel.state == .prepareToReconstruct {
                // Use our enhanced ProcessingProgressView with title and back button
                ProcessingProgressView(progress: appModel.reconstructionProgress)
                    .environmentObject(appModel)
            } else if showProgressView {
                CircularProgressView()
            }
        }
        .onChange(of: appModel.state) { _, newState in
            ContentView.logger.debug("State changed to: \(newState)")
            
            if newState == .capturing {
                // When transitioning to capturing state, set initializing to true briefly
                // to ensure the session is properly set up before showing the capture view
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
                }
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
                .environmentObject(appModel)
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

struct ProcessingProgressView: View {
    let progress: Double
    @EnvironmentObject var appModel: AppDataModel
    
    var body: some View {
        ZStack {
            // Full screen background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            // Main content
            VStack {
                // Top Navigation - Title and Back button
                HStack {
                    // Back Button
                    Button(action: {
                        // Cancel the reconstruction process
                        appModel.photogrammetrySession?.cancel()
                        
                        // Reset everything and go back to capture state
                        appModel.isImagePlacementMode = false
                        appModel.selectedImage = nil
                        appModel.selectedModelEntity = nil
                        appModel.captureType = .objectCapture
                        
                        // Reset the state to restart
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
                
                // Progress indicator
                VStack(spacing: 20) {
                    Text("Processing Scan")
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
                    
                    if progress < 0.01 {
                        Text("Preparing to process...")
                            .foregroundColor(.secondary)
                    } else if progress < 1.0 {
                        Text("Creating 3D model...")
                            .foregroundColor(.secondary)
                    } else {
                        Text("Finalizing model...")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(15)
                .shadow(radius: 5)
                .padding(.horizontal, 40)
                
                Spacer()
                
                // Information text at bottom
                Text("Processing performance depends on your device model and scan complexity.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
            .edgesIgnoringSafeArea(.top)
        }
    }
}
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

#if DEBUG
@available(iOS 17.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
