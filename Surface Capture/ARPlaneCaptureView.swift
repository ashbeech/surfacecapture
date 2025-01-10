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
