//
//  CaptureFolderManager.swift
//  Surface Capture App
//

import Foundation
import os

/// A class that manages the creation and access to capture folders for storing images, snapshots, and models.
class CaptureFolderManager: ObservableObject {
    static let logger = Logger(subsystem: "com.example.SurfaceCapture",
                             category: "CaptureFolderManager")
    
    private let logger = CaptureFolderManager.logger
    
    // The top-level capture directory that contains Images and Snapshots subdirectories
    let rootScanFolder: URL
    
    // Subdirectory of `rootScanFolder` for images
    let imagesFolder: URL
    
    // Subdirectory of `rootScanFolder` for snapshots
    let snapshotsFolder: URL
    
    // Subdirectory to output model files
    let modelsFolder: URL
    
    // Published array of shots for UI updates
    @Published var shots: [ShotFileInfo] = []
    
    // Constants for file naming
    private static let imageStringPrefix = "IMG_"
    private static let heicImageExtension = "HEIC"
    
    init?() {
        // Create the top-level Scans directory with timestamp
        guard let documentsFolder = FileManager.default.urls(for: .documentDirectory,
                                                          in: .userDomainMask).first else {
            logger.error("Cannot access documents directory")
            return nil
        }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let scansBaseFolder = documentsFolder.appendingPathComponent("Scans", isDirectory: true)
        rootScanFolder = scansBaseFolder.appendingPathComponent(timestamp, isDirectory: true)
        
        logger.debug("Creating root scan folder at: \(self.rootScanFolder.path)")
        
        // Define subdirectories
        imagesFolder = rootScanFolder.appendingPathComponent("Images", isDirectory: true)
        snapshotsFolder = rootScanFolder.appendingPathComponent("Snapshots", isDirectory: true)
        modelsFolder = rootScanFolder.appendingPathComponent("Models", isDirectory: true)
        
        // Create all directories with proper error handling
        do {
            try FileManager.default.createDirectory(at: rootScanFolder,
                                                 withIntermediateDirectories: true)
            
            try FileManager.default.createDirectory(at: imagesFolder,
                                                 withIntermediateDirectories: true)
            
            try FileManager.default.createDirectory(at: snapshotsFolder,
                                                 withIntermediateDirectories: true)
            
            try FileManager.default.createDirectory(at: modelsFolder,
                                                 withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create capture directories: \(error.localizedDescription)")
            return nil
        }
        
        // Verify directories were created successfully
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootScanFolder.path, isDirectory: &isDir) && isDir.boolValue,
              FileManager.default.fileExists(atPath: imagesFolder.path, isDirectory: &isDir) && isDir.boolValue,
              FileManager.default.fileExists(atPath: snapshotsFolder.path, isDirectory: &isDir) && isDir.boolValue,
              FileManager.default.fileExists(atPath: modelsFolder.path, isDirectory: &isDir) && isDir.boolValue else {
            logger.error("Directory verification failed")
            return nil
        }
        
        logger.log("Successfully created capture folder structure")
    }
    
    /// Load all image shots from the images folder
    func loadShots() async throws {
        logger.debug("Loading captured images (async)...")
        
        // Get image URLs
        let imgUrls = try FileManager.default
            .contentsOfDirectory(at: imagesFolder,
                               includingPropertiesForKeys: [],
                               options: [.skipsHiddenFiles])
            .filter { $0.isFileURL &&
                     ($0.lastPathComponent.hasSuffix(".HEIC") ||
                      $0.lastPathComponent.hasSuffix(".JPG") ||
                      $0.lastPathComponent.hasSuffix(".jpeg"))
            }
            
        // Process image URLs and create shot info objects
        let shotInfos = imgUrls.compactMap { url -> ShotFileInfo? in
            guard let shotFileInfo = ShotFileInfo(url: url) else {
                logger.error("Can't get shotId from url: \"\(url)\")")
                return nil
            }
            return shotFileInfo
        }
        
        // Sort the shots by ID
        let sortedShots = shotInfos.sorted(by: { $0.id < $1.id })
        
        // Update the published array on the main actor
        await MainActor.run {
            self.shots = sortedShots
        }
    }
    
    /// Retrieves the image id from an existing file at a URL
    ///
    /// - Parameter url: URL of the photo for which this method returns the image id
    /// - Returns: The image ID if `url` is valid; otherwise `nil`
    static func parseShotId(url: URL) -> UInt32? {
        let photoBasename = url.deletingPathExtension().lastPathComponent
        
        guard let endOfPrefix = photoBasename.lastIndex(of: "_") else {
            logger.warning("Can't get endOfPrefix from \(photoBasename)")
            return nil
        }
        
        let imgPrefix = photoBasename[...endOfPrefix]
        guard imgPrefix == imageStringPrefix else {
            logger.warning("Prefix doesn't match!")
            return nil
        }
        
        let idString = photoBasename[photoBasename.index(after: endOfPrefix)...]
        guard let id = UInt32(idString) else {
            logger.warning("Can't convert idString=\"\(idString)\" to uint32!")
            return nil
        }
        
        return id
    }
    
    /// Returns the basename for file with the given `id`
    static func imageIdString(for id: UInt32) -> String {
        return String(format: "%@%04d", imageStringPrefix, id)
    }
    
    /// Returns the file URL for the HEIC image that matches the specified image id in a specified output directory
    ///
    /// - Parameters:
    ///   - outputDir: The directory where the capture session saves images
    ///   - id: Identifier of an image
    /// - Returns: File URL for the image
    static func heicImageUrl(in outputDir: URL, id: UInt32) -> URL {
        return outputDir
            .appendingPathComponent(imageIdString(for: id))
            .appendingPathExtension(heicImageExtension)
    }
}

/// A struct to represent shot file information
struct ShotFileInfo: Identifiable {
    let id: UInt32
    let url: URL
    
    init?(url: URL) {
        guard let id = CaptureFolderManager.parseShotId(url: url) else {
            return nil
        }
        self.id = id
        self.url = url
    }
}
