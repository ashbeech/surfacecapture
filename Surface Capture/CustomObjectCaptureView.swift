//
//  CustomObjectCaptureView.swift
//  Surface Capture App
//

/*
import SwiftUI
import RealityKit
import ARKit
import Combine

@available(iOS 17.0, *)
struct CustomObjectCaptureView: View {
    var session: ObjectCaptureSession
    @State private var pointCloudOpacity: Double = 1.0
    @State private var showPointCloud: Bool = true
    
    var body: some View {
        ZStack {
            // Use Apple's ObjectCaptureView with only documented modifiers
            ObjectCaptureView(session: session)
                .hideObjectReticle(true)  // This is the only documented modifier
                
            // Conditionally add our point cloud visualization
            if showPointCloud {
                ObjectCapturePointCloudView(session: session)
                    .showShotLocations(true)
                    .opacity(pointCloudOpacity)
            }
        }
        .onChange(of: session.state) { _, newState in
            // Show point cloud when capturing
            if case .capturing = newState {
                showPointCloud = true
                withAnimation(.easeIn(duration: 0.5)) {
                    pointCloudOpacity = 1.0
                }
            } else if case .completed = newState {
                // Keep point cloud visible when completed
                showPointCloud = true
                pointCloudOpacity = 1.0
            } else if case .failed = newState {
                // Hide point cloud on failure
                withAnimation {
                    pointCloudOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showPointCloud = false
                }
            }
        }
    }
}
*/
