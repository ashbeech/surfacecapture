//
//  USDAssetResolver.swift
//  Surface Capture App
//

import Foundation
import RealityKit

class USDAssetResolver {
    static func resolveTexturePaths(in usdcURL: URL) throws {
        let snapshotFolder = usdcURL.deletingLastPathComponent()
        let meshID = usdcURL.deletingPathExtension().lastPathComponent
        
        let textureFolder = snapshotFolder.appendingPathComponent("0")
        
        // Read USDC file content
        var usdcContent = try String(contentsOf: usdcURL, encoding: .utf8)
        
        // Update texture references
        let textureTypes = ["ao0", "norm0", "tex0"]
        for type in textureTypes {
            let oldPath = "@0/\(meshID)_\(type).png@"
            let newPath = "@\(textureFolder.path)/\(meshID)_\(type).png@"
            usdcContent = usdcContent.replacingOccurrences(of: oldPath, with: newPath)
        }
        
        // Write updated content back
        try usdcContent.write(to: usdcURL, atomically: true, encoding: .utf8)
    }
    
    static func moveTexturesToExpectedLocation(from sourceURL: URL) throws {
        let snapshotFolder = sourceURL.deletingLastPathComponent()
        let meshID = sourceURL.deletingPathExtension().lastPathComponent
        
        let textureFolder = snapshotFolder.appendingPathComponent("0")
        try FileManager.default.createDirectory(at: textureFolder, withIntermediateDirectories: true)
        
        // Move texture files
        let textureTypes = ["ao0", "norm0", "tex0"]
        for type in textureTypes {
            let textureName = "\(meshID)_\(type).png"
            let sourceFile = snapshotFolder.appendingPathComponent(textureName)
            let destinationFile = textureFolder.appendingPathComponent(textureName)
            
            if FileManager.default.fileExists(atPath: sourceFile.path) {
                try FileManager.default.moveItem(at: sourceFile, to: destinationFile)
            }
        }
    }
}
