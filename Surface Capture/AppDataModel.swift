import Combine
import RealityKit
import SwiftUI
import os

enum AppError: Error {
    case emptyModelFile
    case modelFileNotFound
    case insufficientImages(Int)
    case reconstructionFailed
    case invalidInputImages
    case processingError(String)
    case fileSystemError(String)
    
    var localizedDescription: String {
        switch self {
        case .emptyModelFile:
            return "The generated model file is empty"
        case .modelFileNotFound:
            return "The model file could not be found"
        case .insufficientImages(let count):
            return "Not enough images captured (need at least 10, got \(count))"
        case .reconstructionFailed:
            return "Failed to reconstruct the 3D model - Please try capturing again"
        case .invalidInputImages:
            return "Invalid or corrupted input images"
        case .processingError(let details):
            return "Processing error: \(details)"
        case .fileSystemError(let details):
            return "File system error: \(details)"
        }
    }
}

@MainActor
@available(iOS 17.0, *)
class AppDataModel: ObservableObject, Identifiable {
    let logger = Logger(subsystem: "com.example.SurfaceCapture",
                       category: "AppDataModel")
    
    static let instance = AppDataModel()
    
    @Published var captureQualityMetrics = CaptureQualityMetrics()
    @Published var captureQualityStatus: CaptureQualityStatus = .good
    
    @Published var objectCaptureSession: ObjectCaptureSession? {
        willSet {
            detachListeners()
        }
        didSet {
            guard objectCaptureSession != nil else { return }
            attachListeners()
        }
    }
    
    static let minNumImages = 3
    private(set) var photogrammetrySession: PhotogrammetrySession?
    private(set) var scanFolderManager: CaptureFolderManager!
    @Published var messageList = TimedMessageList()
    
    @Published var state: ModelState = .notSet {
        didSet {
            logger.debug("didSet AppDataModel.state to \(self.state)")
            if state != oldValue {
                performStateTransition(from: oldValue, to: state)
            }
        }
    }
    
    private(set) var error: Swift.Error?
    
    private init() {
        state = .ready
    }
    
    private var tasks: [Task<Void, Never>] = []
    
    private func attachListeners() {
        logger.debug("Attaching listeners...")
        guard let model = objectCaptureSession else { return }
        
        tasks.append(Task<Void, Never> { [weak self] in
            for await newState in model.stateUpdates {
                self?.logger.debug("Task got async state change to: \(String(describing: newState))")
                self?.onStateChanged(newState: newState)
            }
            self?.logger.log("Finished state updates observation")
        })
    }
    
    private func detachListeners() {
        logger.debug("Detaching listeners...")
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
    
    private func startNewCapture() -> Bool {
        logger.log("Starting new capture...")
        guard ObjectCaptureSession.isSupported else {
            logger.error("ObjectCaptureSession not supported on this device")
            return false
        }
        
        guard let folderManager = CaptureFolderManager() else {
            logger.error("Failed to create folder manager")
            return false
        }
        
        scanFolderManager = folderManager
        objectCaptureSession = ObjectCaptureSession()
        
        guard let session = objectCaptureSession else {
            logger.error("Failed to create capture session")
            return false
        }
        
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = scanFolderManager.snapshotsFolder
        configuration.isOverCaptureEnabled = true // Enable over-capture for better coverage
        
        session.start(imagesDirectory: scanFolderManager.imagesFolder,
                     configuration: configuration)
        
        if case let .failed(error) = session.state {
            logger.error("Session failed to start: \(String(describing: error))")
            switchToErrorState(error: error)
            return false
        } else {
            state = .capturing
            return true
        }
    }
    
    @Published var reconstructionProgress: Double = 0
    
    private func verifyReconstructionAssets(baseFolder: URL, snapshotID: String) -> Bool {
        let snapshotFolder = baseFolder.appendingPathComponent("Snapshots").appendingPathComponent(snapshotID)
        
        // Check for base mesh USDC file
        let meshFileName = "baked_mesh_\(snapshotID).usdc"
        let meshFile = snapshotFolder.appendingPathComponent(meshFileName)
        
        guard FileManager.default.fileExists(atPath: meshFile.path) else {
            logger.error("Base mesh file missing at: \(meshFile.path)")
            return false
        }
        
        // Check for required texture assets
        let requiredAssets = ["ao0.png", "norm0.png", "tex0.png"]
        let assetPrefix = "baked_mesh_\(snapshotID)"
        
        let missingAssets = requiredAssets.filter { assetSuffix in
            let assetName = "\(assetPrefix)_\(assetSuffix)"
            let assetPath = snapshotFolder.appendingPathComponent("0").appendingPathComponent(assetName)
            let exists = FileManager.default.fileExists(atPath: assetPath.path)
            if !exists {
                logger.error("Missing required asset: \(assetPath.path)")
            }
            return !exists
        }
        
        return missingAssets.isEmpty
    }
    
    private func extractSnapshotID(from outputFile: URL) throws -> String? {
        let fileURL = outputFile.deletingLastPathComponent()
        let contents = try FileManager.default.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil)
        
        // Look for snapshot folders
        let snapshotFolders = contents.filter { url in
            url.lastPathComponent.contains("Snapshots")
        }
        
        // Extract snapshot ID from folder structure
        if let snapshotFolder = snapshotFolders.first {
            let subfolders = try FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)
            // Look for folders with UUID format
            return subfolders.first { url in
                let folderName = url.lastPathComponent
                return folderName.count == 36 && folderName.contains("-")
            }?.lastPathComponent
        }
        
        return nil
    }
    
    private func startReconstruction() throws {
        logger.debug("Starting reconstruction...")
               reconstructionProgress = 0
               
               // Ensure clean state before starting
               let outputFile = scanFolderManager.modelsFolder.appendingPathComponent("model-mobile.usdz")
               try? FileManager.default.removeItem(at: outputFile)
               
               // Create model directory if it doesn't exist
               try FileManager.default.createDirectory(at: scanFolderManager.modelsFolder,
                                                     withIntermediateDirectories: true)
               
               // Configure for reliable reconstruction with optimized settings
               var configuration = PhotogrammetrySession.Configuration()
               configuration.checkpointDirectory = scanFolderManager.snapshotsFolder
               configuration.sampleOrdering = .unordered // Handle out-of-order frames better
               configuration.featureSensitivity = .normal // More stable than .high
               
               // Verify input images before starting
               do {
                   let imageFiles = try FileManager.default.contentsOfDirectory(at: scanFolderManager.imagesFolder,
                                                                              includingPropertiesForKeys: [.fileSizeKey])
                   guard !imageFiles.isEmpty else {
                       logger.error("No input images found")
                       throw AppError.reconstructionFailed
                   }
                   
                   // Add minimum image count check here
                   guard imageFiles.count >= AppDataModel.minNumImages else {
                       logger.error("Insufficient number of images: \(imageFiles.count)")
                       throw AppError.insufficientImages(imageFiles.count)
                   }
                   
                   // Verify image files are valid and have sufficient size
                   for imageFile in imageFiles {
                       let attributes = try FileManager.default.attributesOfItem(atPath: imageFile.path)
                       guard let size = attributes[.size] as? UInt64, size > 100000 else { // Minimum size threshold
                           logger.error("Found potentially invalid image file: \(imageFile.lastPathComponent)")
                           throw AppError.invalidInputImages
                       }
                   }
                   
                   logger.debug("Found \(imageFiles.count) valid input images")
               } catch {
                   logger.error("Failed to verify input images: \(error)")
                   throw AppError.reconstructionFailed
               }
               
               // Attempt to create session with retries
               var session: PhotogrammetrySession?
               var sessionError: Error?
               let maxSessionRetries = 3
               
               for attempt in 1...maxSessionRetries {
                   do {
                       session = try PhotogrammetrySession(
                           input: scanFolderManager.imagesFolder,
                           configuration: configuration)
                       break
                   } catch {
                       sessionError = error
                       logger.error("Session creation attempt \(attempt) failed: \(error)")
                       if attempt < maxSessionRetries {
                           Thread.sleep(forTimeInterval: 1.0)
                       }
                   }
               }
               
               guard let photogrammetrySession = session else {
                   throw sessionError ?? AppError.reconstructionFailed
               }
               
               self.photogrammetrySession = photogrammetrySession
        
        // Use lowest detail level for reliable processing
        let request = PhotogrammetrySession.Request.modelFile(
            url: outputFile,
            detail: .reduced) // Changed from .preview to .reduced
        
        Task {
            do {
                // Use Task.sleep instead of Thread.sleep
                try await Task.sleep(for: .seconds(1))
                
                var processingError: Error?
                try photogrammetrySession.process(requests: [request])
                
                for try await output in photogrammetrySession.outputs {
                    switch output {
                    case .processingComplete:
                        logger.debug("Processing complete")
                        reconstructionProgress = 1.0
                        
                        // Verification with retries
                        let maxRetries = 3
                        var retryCount = 0
                        var modelFileFound = false
                        
                        while retryCount < maxRetries && !modelFileFound {
                            if retryCount > 0 {
                                try await Task.sleep(for: .seconds(1))
                            }
                            
                            if FileManager.default.fileExists(atPath: outputFile.path) {
                                let attributes = try? FileManager.default.attributesOfItem(atPath: outputFile.path)
                                 if let size = attributes?[.size] as? UInt64, size > 0 {
                                     do {
                                         let data = try Data(contentsOf: outputFile)
                                         if data.count > 0 {
                                             // Extract snapshot ID and handle texture paths
                                             if let snapshotID = try extractSnapshotID(from: outputFile) {
                                                 let snapshotFolder = scanFolderManager.snapshotsFolder.appendingPathComponent(snapshotID)
                                                 let meshFiles = try FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)
                                                     .filter { $0.pathExtension == "usdc" }
                                                 
                                                 for meshFile in meshFiles {
                                                     try USDAssetResolver.resolveTexturePaths(in: meshFile)
                                                     try USDAssetResolver.moveTexturesToExpectedLocation(from: meshFile)
                                                 }
                                             }
                                             
                                             modelFileFound = true
                                             logger.debug("Model file verified on attempt \(retryCount + 1)")
                                             DispatchQueue.main.async { [weak self] in
                                                 self?.state = .viewing
                                             }
                                             break
                                         }
                                     } catch {
                                         logger.error("Failed to read model file on attempt \(retryCount + 1): \(error)")
                                     }
                                 }
                            }
                            retryCount += 1
                            
                            if retryCount == maxRetries {
                                logger.error("Failed to verify model file after \(maxRetries) attempts")
                                throw AppError.modelFileNotFound
                            }
                        }
                        
                    case .requestError(_, let error):
                        logger.error("Reconstruction failed: \(error)")
                        processingError = error
                        break
                        
                    case .requestProgress(_, let fractionComplete):
                        logger.debug("Progress: \(fractionComplete * 100)%")
                        DispatchQueue.main.async {
                            self.reconstructionProgress = fractionComplete
                        }
                        
                    default:
                        break
                    }
                }
                
                if let error = processingError {
                    throw error
                }
                
            } catch {
                logger.error("Reconstruction failed: \(error)")
                if let photoError = error as? PhotogrammetrySession.Error {
                    // Map PhotogrammetrySession error to our app error
                    let appError = AppError.processingError("Photogrammetry error: \(photoError)")
                    switchToErrorState(error: appError)
                } else {
                    switchToErrorState(error: AppError.reconstructionFailed)
                }
            }
        }
        
        state = .reconstructing
    }
    
    private func switchToErrorState(error: Swift.Error) {
        self.error = error
        state = .failed
    }
    
    private func onStateChanged(newState: ObjectCaptureSession.CaptureState) {
        logger.info("Session state changed to: \(String(describing: newState))")
        switch newState {
        case .completed:
            logger.log("Capture completed, starting reconstruction...")
            state = .prepareToReconstruct
        case .failed(let error):
            logger.error("Capture failed: \(String(describing: error))")
            switchToErrorState(error: error)
        default:
            break
        }
    }
    
    private func performStateTransition(from fromState: ModelState, to toState: ModelState) {
        if fromState == .failed {
            error = nil
        }
        
        switch toState {
        case .ready:
            guard startNewCapture() else {
                logger.error("Failed to start new capture")
                break
            }
        case .prepareToReconstruct:
            objectCaptureSession = nil
            do {
                try startReconstruction()
            } catch {
                logger.error("Failed to start reconstruction: \(error)")
                switchToErrorState(error: error)
            }
        case .viewing:
            photogrammetrySession = nil
        case .restart, .completed:
            reset()
        case .failed:
            logger.error("App failed with error: \(String(describing: self.error))")
        default:
            break
        }
    }
    
    private func reset() {
        // Add guard to prevent duplicate cleanup
        guard objectCaptureSession != nil || photogrammetrySession != nil else { return }
        logger.info("Resetting app state...")
        photogrammetrySession = nil
        objectCaptureSession = nil
        scanFolderManager = nil
        state = .ready
    }
    
    func endCapture() {
        state = .completed
    }
}

extension AppDataModel {
    enum ModelState: String, CustomStringConvertible {
        var description: String { rawValue }
        
        case notSet
        case ready
        case capturing
        case prepareToReconstruct
        case reconstructing
        case viewing
        case completed
        case restart
        case failed
    }
}
