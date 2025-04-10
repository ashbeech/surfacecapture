//
//  AppDataModel.swift
//  Surface Capture App
//

import Combine
import RealityKit
import SwiftUI
import os

// Add capture type enum to differentiate between modes
enum CaptureType {
    case objectCapture
    case imagePlane
}

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
    
    let logger = Logger(subsystem: "com.example.SurfaceCapture", category: "AppDataModel")
    static let instance = AppDataModel()
    var arViewController: ARPlaneCaptureViewController?
    @Published var selectedModelEntity: ModelEntity?
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
    static let minNumImages = 5
    private(set) var photogrammetrySession: PhotogrammetrySession?
    private(set) var scanFolderManager: CaptureFolderManager!
    @Published var messageList = TimedMessageList()
    @Published var modelOpacity: Double = 0.9
    @Published var state: ModelState = .notSet {
        didSet {
            logger.debug("didSet AppDataModel.state to \(self.state)")
            if state != oldValue {
                performStateTransition(from: oldValue, to: state)
            }
        }
    }
    // Image picker properties
    @Published var captureType: CaptureType = .objectCapture
    @Published var selectedImage: UIImage?
    @Published var isImagePlacementMode: Bool = false
    @Published var isShowingPlacementInstructions: Bool = false
    @Published var isPulsing: Bool = false
    @Published var isImagePickerPresented: Bool = false

    private var stateMonitoringTask: Task<Void, Never>?
    @Published var reconstructionProgress: Double = 0
    
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
    
    // Handle selected image
    func handleSelectedImage(_ image: UIImage?) {
        guard let image = image else { return }
        
        // Update image and state
        selectedImage = image
        captureType = .imagePlane
        
        // First, properly clean up any existing capture session and monitoring task
        if objectCaptureSession != nil {
            // Cancel the session
            objectCaptureSession?.cancel()
            
            // Cancel state monitoring task
            stateMonitoringTask?.cancel()
            stateMonitoringTask = nil
            
            // Clear the session
            objectCaptureSession = nil
        }
        
        // Create plane entity
        if selectedModelEntity == nil {
            selectedModelEntity = ImagePlaneEntity.create(from: image)
        } else {
            if let entity = selectedModelEntity {
                ImagePlaneEntity.updateTexture(entity, with: image)
            }
        }
        
        // Set flags for placement mode
        isImagePlacementMode = true
        isShowingPlacementInstructions = true
        
        // Important: Change state last to trigger view updates
        state = .ready
    }
    
    // Toggle image pulsing effect
    func toggleImagePulsing() {
        isPulsing.toggle()
        
        guard let entity = selectedModelEntity else { return }
        
        if isPulsing {
            OpacityManager.startPulsing(entity)
        } else {
            OpacityManager.stopPulsing(entity)
        }
    }
    
    // MARK: - Object Capture Functionality
    func startNewCapture() -> Bool {
        logger.log("Starting new capture...")
        
        // Reset any existing state or sessions
        if objectCaptureSession != nil {
            logger.debug("Cleaning up existing capture session before starting new one")
            objectCaptureSession?.cancel()
            objectCaptureSession = nil
        }
        
        // Check device support first
        guard ObjectCaptureSession.isSupported else {
            logger.error("Object capture is not supported on this device")
            let error = NSError(domain: "com.example.SurfaceCapture",
                                code: 1001,
                                userInfo: [NSLocalizedDescriptionKey: "Your device doesn't support object capture"])
            switchToErrorState(error: error)
            return false
        }
        
        // Create folder manager with proper error handling
        guard let folderManager = CaptureFolderManager() else {
            logger.error("Failed to create folder manager for capture storage")
            let error = NSError(domain: "com.example.SurfaceCapture",
                                code: 1002,
                                userInfo: [NSLocalizedDescriptionKey: "Could not create storage for capture. Please check device storage."])
            switchToErrorState(error: error)
            return false
        }

        scanFolderManager = folderManager
        
        // Initialize ObjectCaptureSession
        let session = ObjectCaptureSession()
        self.objectCaptureSession = session
        
        var configuration = ObjectCaptureSession.Configuration()
        configuration.checkpointDirectory = scanFolderManager.snapshotsFolder
        configuration.isOverCaptureEnabled = false // Enable over-capture for better coverage
        
        
        // Launch a task to monitor initialization
        Task {
            await monitorSessionInitialization(session)
        }
        
        // Start the session
        session.start(imagesDirectory: scanFolderManager.imagesFolder, configuration: configuration)
        
        // Monitor the session for failures
        monitorSessionState(session)
                
        return true
    }

    // Add this separate async method to handle initialization monitoring
    private func monitorSessionInitialization(_ session: ObjectCaptureSession) async {
        // Remove 'try' keyword and do-catch block
        for await state in session.stateUpdates {
            logger.debug("Session state update during initialization: \(String(describing: state))")

            switch state {
            case .ready, .detecting:
                // Session is initialized and ready to use
                logger.debug("Session is ready for capture")
                await MainActor.run {
                    // Update UI to show capture interface
                    self.state = .capturing
                }
                return // Exit the monitoring loop once we reach ready state
                
            case .failed(let error):
                logger.error("Session initialization failed: \(String(describing: error))")
                await MainActor.run {
                    self.switchToErrorState(error: error)
                }
                return // Exit the monitoring loop on failure
                
            case .completed:
                // This should not happen during initialization, but handle it anyway
                logger.debug("Session completed unexpectedly during initialization")
                return
                
            default:
                // Other states like initializing are expected during startup
                logger.debug("Session in transition state: \(String(describing: state))")
            }
        }
        
        // If we exit the loop normally (which shouldn't happen), log it
        logger.debug("Session state monitoring loop exited normally")
    }

    /// Sets up state monitoring for the session to catch failures after initialization
    private func monitorSessionState(_ session: ObjectCaptureSession) {
        // Cancel any existing monitoring task
        stateMonitoringTask?.cancel()
        
        // Create a new task to monitor session state changes
        stateMonitoringTask = Task { [weak self] in
            do {
                // Wait a short time to allow the session to initialize
                try await Task.sleep(for: .seconds(0.5))
                
                // Check if session entered a failure state during initialization
                if case let .failed(error) = session.state {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        logger.error("Session failed during initialization: \(String(describing: error))")
                        switchToErrorState(error: error)
                    }
                    return
                }
                
                // Continue monitoring state for later failures
                for try await state in session.stateUpdates {
                    if case let .failed(error) = state {
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            logger.error("Session failed during operation: \(String(describing: error))")
                            switchToErrorState(error: error)
                        }
                        break
                    }
                }
            } catch {
                // Handle task cancellation gracefully
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        logger.error("Error monitoring session state: \(error)")
                    }
                }
            }
        }
    }

    func endObjectCaptureSession() {
        // Log the operation
        print("Ending ObjectCaptureSession gracefully...")
        
        // First, properly clean up any existing capture session and monitoring task
        if objectCaptureSession != nil {
            // Cancel the session
            objectCaptureSession?.cancel()
            
            // Cancel state monitoring task
            stateMonitoringTask?.cancel()
            stateMonitoringTask = nil
            
            // Clear the session
            objectCaptureSession = nil
            
            // Log successful cleanup
            print("ObjectCaptureSession successfully cleaned up")
        } else {
            print("No ObjectCaptureSession to clean up")
        }
        
        // Reset any related state
        reconstructionProgress = 0
        
        // Reset state
        state = .ready
        
        // Log completion
        print("endObjectCaptureSession completed")
    }
    
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
        try FileManager.default.createDirectory(at: scanFolderManager.modelsFolder, withIntermediateDirectories: true)

        // Configure for reliable reconstruction with optimized settings
        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = scanFolderManager.snapshotsFolder
        configuration.sampleOrdering = .unordered // Handle out-of-order frames better
        configuration.isObjectMaskingEnabled = false
        configuration.featureSensitivity = .normal // More stable than .high

        // Verify input images before starting
        do {
            let imageFiles = try FileManager.default.contentsOfDirectory(at: scanFolderManager.imagesFolder, includingPropertiesForKeys: [.fileSizeKey])
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
                session = try PhotogrammetrySession(input: scanFolderManager.imagesFolder, configuration: configuration)
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
        let request = PhotogrammetrySession.Request.modelFile(url: outputFile, detail: .reduced) // Changed from .preview to .reduced

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
                        //logger.debug("Progress: \(fractionComplete * 100)%")
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
            if captureType == .objectCapture {
                guard startNewCapture() else {
                    logger.error("Failed to start new capture")
                    break
                }
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
            // If in image placement mode, don't clear photogrammetry session
            if captureType == .objectCapture {
                photogrammetrySession = nil
            }
        case .restart:
            // Ensure we properly reset state when restarting
            reset()
            // If we were in image plane mode, reset that too
            if captureType == .imagePlane {
                captureType = .objectCapture
                isImagePlacementMode = false
                selectedImage = nil
                selectedModelEntity = nil
            }
        case .cancelled:
            logger.error("Cancelled")
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
        case initializing
        case ready
        case capturing
        case prepareToReconstruct
        case reconstructing
        case viewing
        case completed
        case restart
        case cancelled
        case failed
    }
}
