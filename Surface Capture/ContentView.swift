//
//  ContentView.swift
//  Surface Capture
//
//  Created by Ashley Davison on 03/01/2025.
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
    
    private var showProgressView: Bool {
        appModel.state == .completed || appModel.state == .restart || appModel.state == .ready
    }
    
    var body: some View {
        VStack {
            if let modelURL = capturedModelURL {
                ARPlaneCaptureView(capturedModelURL: modelURL)
                    .ignoresSafeArea()
            } else if appModel.state == .capturing {
                if let session = appModel.objectCaptureSession {
                    CapturePrimaryView(session: session)
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
            if newState == .failed {
                showErrorAlert = true
                showReconstructionView = false
            } else if newState == .viewing {
                // Only show reconstruction view when model is ready to view
                showReconstructionView = true
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
