//
//  CaptureFolderManager.swift
//  Surface Capture App
//

import Foundation
import os

class CaptureFolderManager: ObservableObject {
    static let logger = Logger(subsystem: "com.example.SurfaceCapture",
                             category: "CaptureFolderManager")
    
    let rootScanFolder: URL
    let imagesFolder: URL
    let snapshotsFolder: URL
    let modelsFolder: URL
    
    init?() {
        guard let documentsFolder = FileManager.default.urls(for: .documentDirectory,
                                                           in: .userDomainMask).first else { return nil }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        rootScanFolder = documentsFolder.appendingPathComponent("Scans/\(timestamp)")
        
        imagesFolder = rootScanFolder.appendingPathComponent("Images")
        snapshotsFolder = rootScanFolder.appendingPathComponent("Snapshots")
        modelsFolder = rootScanFolder.appendingPathComponent("Models")
        
        // Create directories
        try? FileManager.default.createDirectory(at: rootScanFolder,
                                               withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesFolder,
                                               withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: snapshotsFolder,
                                               withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modelsFolder,
                                               withIntermediateDirectories: true)
    }
}
