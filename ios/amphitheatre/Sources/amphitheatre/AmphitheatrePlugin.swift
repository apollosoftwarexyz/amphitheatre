import Flutter
import UIKit
import Foundation
import AVFoundation

let PLUGIN_BUNDLE_ID = "xyz.apollosoftware.amphitheatre"
let EVENT_CHANNEL_ID = "events"

/// An extension to the FlutterError type that conforms to Error.
///
/// This enables `FlutterError` to be thrown like a normal error.
extension FlutterError: Error {}

/// A Task that encapsulates an ``AmphitheatreExportSession``.
public typealias AmphitheatreExportTask = Task<String, Error>

public class AmphitheatreExportSession {
    /// The `FlutterPluginRegistrar` (i.e., Flutter app) that started the export session.
    let registrar: FlutterPluginRegistrar
    /// The asynchronous `Task` that encapsulates the export session.
    let task: AmphitheatreExportTask
    /// The event sink for the export session - where progress updates should be delivered.
    var sink: FlutterEventSink?
    
    init(registrar: FlutterPluginRegistrar, task: AmphitheatreExportTask) {
        self.registrar = registrar
        self.task = task
    }
    
    /// Bind the given `FlutterEventSink` to the export session.
    ///
    /// Once the event sink is bound, progress updates will be delivered to the event sink as they become available.
    public func bind(sink: @escaping FlutterEventSink) throws(FlutterError) {
        if self.sink != nil {
            throw FlutterError(code: "CONFLICTING_BIND", message: "Tried to bind an event sink to a session that was already bound.", details: nil)
        }
        
        self.sink = sink
    }
    
    /// Deliver the status update to Flutter.
    public func notify(status: Any) {
        self.sink?(status)
    }
    
    /// Cancel the export session.
    public func cancel() {
        self.task.cancel()
    }
}

public class AmphitheatrePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    
    private let registrar: FlutterPluginRegistrar
    private var sessions: [String: AmphitheatreExportSession] = [:]
    
    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
    }
    
    @objc
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        
        let channel = FlutterMethodChannel(name: PLUGIN_BUNDLE_ID, binaryMessenger: messenger)
        let eventChannel = FlutterEventChannel(name: "\(PLUGIN_BUNDLE_ID)/\(EVENT_CHANNEL_ID)", binaryMessenger: messenger)

        let instance = AmphitheatrePlugin(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    @objc
    public func detachFromEngine(for registrar: any FlutterPluginRegistrar) {
        cleanUp()
    }
    
    // This is unfortunately required to work around a limitation in Flutter's
    // hot reload (there is no way to detect it in platform code).
    public func cleanUp() {
        NSLog("Performing clean-up.")
        
        for (sessionId, session) in sessions {
            NSLog("Found session.")
            if session.registrar.isEqual(registrar) {
                NSLog("Cleaning up session: \(sessionId)")
                session.cancel()
            }
        }
    }
    
    public struct SessionArgs {
        let sessionId: String
        
        public static func parse(arguments: Any?) throws(FlutterError) -> SessionArgs {
            guard let rawArgs = arguments as? NSDictionary,
                  let sessionId = rawArgs["sessionId"] as? NSString as? String
            else {
                throw FlutterError(code: "INVALID_ARGS", message: "Invalid arguments for stream", details: nil)
            }
            
            return SessionArgs(sessionId: sessionId)
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if (arguments == nil) {
            return nil
        }
        
        do {
            let args = try SessionArgs.parse(arguments: arguments)
            NSLog("onListen: %@", args.sessionId)
            
            switch sessions[args.sessionId] {
                case .some(let session): try session.bind(sink: events)
                case .none: return FlutterError(code: "UNKNOWN_SESSION", message: "Invalid session ID.", details: args.sessionId)
            }

            return nil
        } catch let error {
            return error
        }
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if (arguments == nil) {
            return nil
        }
        
        do {
            let args = try SessionArgs.parse(arguments: arguments)
            try cancelCropVideo(sessionId: args.sessionId)
            return nil
        } catch let error {
            return error
        }
    }
    
    public func cancelCropVideo(sessionId: String) throws(FlutterError) -> Bool {
        let session = sessions.removeValue(forKey: sessionId)
        if session == nil {
            NSLog("WARNING: Called cancelCropVideo for an unknown session ID: %@", sessionId)
            return false
        }
        
        NSLog("cancelCropVideo: %@", sessionId)
        try session!.cancel()
        return true
    }
    
    @objc
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        
        Task.init {
            do {
                switch call.method {
                    case "_init":
                        self.cleanUp()
                        result(true)
                    case "getTemporaryDirectory": result(try await getTemporaryDirectory())
                    case "deleteFile": result(try await deleteFile(args: try DeleteFileArgs.parse(arguments: call.arguments)))
                    case "startCropVideo": result(try await startCropVideo(args: try CropVideoArgs.parse(arguments: call.arguments)))
                    case "awaitCropVideo": result(try await awaitCropVideo(args: try SessionArgs.parse(arguments: call.arguments)))
                    default: result(FlutterMethodNotImplemented)
                }
            } catch let error as CancellationError {
                result(FlutterError(code: "ERR_CANCELLED", message: "Cancelled.", details: nil))
            } catch let error as FlutterError {
                result(error)
            }
        }

    }
    
    public struct DeleteFileArgs {
        let path: String
        
        public static func parse(arguments: Any?) throws(FlutterError) -> DeleteFileArgs {
            guard let rawArgs = arguments as? NSDictionary,
                  let path = rawArgs["path"] as? NSString as? String
            else {
                throw FlutterError(code: "INVALID_ARGS", message: "Invalid arguments for deleteFile", details: nil)
            }
            
            return DeleteFileArgs(path: path)
        }
    }
    
    private func deleteFile(args: DeleteFileArgs) throws(FlutterError) {
        do {
            try FileManager.default.removeItem(atPath: args.path)
        } catch let error {
            throw FlutterError(code: "FILE_REMOVAL_FAILED", message: "Failed to delete file at path.", details: args.path)
        }
    }
    
    private func getTemporaryDirectory() throws(FlutterError) -> String {
        // Compute a plugin-specific temporary directory path.
        let path: String
        if #available(iOS 16.0, *) {
            path = FileManager.default.temporaryDirectory.appending(path: PLUGIN_BUNDLE_ID).path(percentEncoded: false)
        } else {
            path = FileManager.default.temporaryDirectory.appendingPathComponent(PLUGIN_BUNDLE_ID).path
        }
        
        // Ensure the directory exists.
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch let error {
            // Given withIntermediateDirectories is true, this will
            // not error if the directory already exists.
            throw FlutterError(code: "TEMPORARY_DIRECTORY", message: "Failed to create a package-specific temporary directory.", details: ["error": error])
        }
        
        // Return the path to the directory, on success.
        return path
    }
    
    public enum CropVideoQuality: String {
        case presetHD = "presetHD"
        case presetFullHD = "presetFullHD"
        case highest = "highest"
        case passthrough = "passthrough"
        
        static let defaultQuality: CropVideoQuality = CropVideoQuality.presetFullHD
        
        func asExportPreset() -> String {
            switch (self) {
                case .presetHD: return AVAssetExportPreset1280x720
                case .presetFullHD: return AVAssetExportPreset1920x1080
                case .highest: return AVAssetExportPresetHighestQuality
                case .passthrough: return AVAssetExportPresetPassthrough
            }
        }
    }
    
    public class CropVideoArgs {
        let path: String
        let start: UInt64
        let end: UInt64
        let quality: CropVideoQuality
        
        init(path: String, start: UInt64, end: UInt64, quality: CropVideoQuality) {
            self.path = path
            self.start = start
            self.end = end
            self.quality = quality
        }
        
        public static func parse(arguments: Any) throws(FlutterError) -> CropVideoArgs {
            guard let rawArgs = arguments as? NSDictionary,
                  let path = (rawArgs["path"] as? NSString) as? String,
                  let start = (rawArgs["start"] as? NSNumber)?.uint64Value,
                  let end = (rawArgs["end"] as? NSNumber)?.uint64Value,
                  let rawQuality = ((rawArgs["quality"] as? NSString) ?? "default") as? String,
                  let quality = rawQuality == "default" ? CropVideoQuality.defaultQuality : CropVideoQuality(rawValue: rawQuality)
            else {
              throw FlutterError(code: "INVALID_ARGS", message: "Invalid arguments for cropVideo", details: nil)
            }
            
            return CropVideoArgs(path: path, start: start, end: end, quality: quality)
        }
    }
    
    private func getNewSessionId() -> String {
        var sessionId: String? = nil
        
        while (sessionId == nil || sessions.keys.contains(sessionId!)) {
            sessionId = UUID().uuidString
        }
        
        return sessionId!
    }
    
    public func startCropVideo(args: CropVideoArgs) async throws(FlutterError) -> String {
        let sessionId = getNewSessionId()
        
        // If the session ID is already registered, fail.
        if sessions.keys.contains(sessionId) {
            throw FlutterError(code: "ALREADY_BOUND", message: "The given session ID is already registered.", details: nil)
        }
        
        // Ensure the specified path exists and is not a directory.
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: args.path, isDirectory: &isDirectory) {
            throw FlutterError(code: "SEARCH_FAIL", message: "Failed to locate the provided file path.", details: nil)
        }
        
        // Then, convert the input path to an AVURLAsset.
        let url: URL
        if #available(iOS 16.0, *) {
            url = URL.init(filePath: args.path, directoryHint: URL.DirectoryHint.notDirectory)
        } else {
            url = URL(fileURLWithPath: args.path, isDirectory: false)
        }
        let asset: AVURLAsset = AVURLAsset.init(url: url)
        
        // Define the time range to crop the video to.
        let startTime = CMTime(seconds: Double(args.start)/1000, preferredTimescale: 1000)
        let endTime = CMTime(seconds: Double(args.end)/1000, preferredTimescale: 1000)
        let timeRange = CMTimeRange(start: startTime, end: endTime)
        
        // Compute the new file extension (.out.<ext>).
        let pathExtension = asset.url.pathExtension
        var outUrl: URL
        if #available(iOS 16.0, *) {
            outUrl = URL.init(filePath: asset.url.path(), directoryHint: URL.DirectoryHint.notDirectory)
        } else {
            outUrl = URL.init(fileURLWithPath: asset.url.path, isDirectory: false)
        }
        outUrl.deletePathExtension()
        outUrl = outUrl.appendingPathExtension("out.\(pathExtension)")
        
        // Attempt to remove any existing file at outUrl.
        _ = try? FileManager.default.removeItem(at: outUrl)
        
        // Configure the export session.
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: args.quality.asExportPreset()) else {
            throw FlutterError(code: "FAILED_TO_CREATE_EXPORT_SESSION", message: "Failed to initialize an export session.", details: nil)
        }

        exportSession.timeRange = timeRange
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Start the file export.
        let task = AmphitheatreExportTask {
            if #available(iOS 18, *) {
                async let export = exportSession.export(to: outUrl, as: AVFileType.mp4)
                
                for await state in exportSession.states(updateInterval: 0.1) {
                    if case .exporting(let progress) = state {
                        self.handleCropVideoProgress(sessionId: sessionId, args: args, progress: progress.fractionCompleted)
                    }
                }
                
                do {
                    try await export
                    
                    // On success, ensure 100% is reported.
                    self.handleCropVideoProgress(sessionId: sessionId, args: args, progress: 1.0)
                } catch let error {
                    if error is CancellationError {
                        throw FlutterError(code: "EXPORT_CANCELLED", message: "The export session was cancelled.", details: error.localizedDescription)
                    }
                    
                    throw FlutterError(code: "EXPORT_FAILED", message: "An error occurred during the export session.", details: error.localizedDescription)
                }
            } else {
                
                exportSession.outputURL = outUrl
                exportSession.outputFileType = AVFileType.mp4
                
                DispatchQueue.main.async {
                    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        let progress = exportSession.progress
                        if (progress >= 1.0 || ![.unknown, .waiting, .exporting].contains(exportSession.status)) {
                            timer.invalidate()
                        }
                        
                        self.handleCropVideoProgress(sessionId: sessionId, args: args, progress: Double(progress))
                    }
                }
                
                await exportSession.export()
                
                switch exportSession.status {
                case .completed:
                    self.handleCropVideoProgress(sessionId: sessionId, args: args, progress: 1.0)
                case .failed:
                    throw FlutterError(code: "EXPORT_FAILED", message: "The export session failed.", details: nil)
                case .cancelled:
                    throw FlutterError(code: "EXPORT_CANCELLED", message: "The export session was cancelled.", details: nil)
                case .unknown: fallthrough
                case .waiting: fallthrough
                case .exporting:
                    throw FlutterError(code: "EXPORT_STATE_INVALID", message: "The export session ended in an illegal state ('\(exportSession.status)').", details: nil)
                }
            }
            
            if #available(iOS 16.0, *) {
                return outUrl.path()
            } else {
                return outUrl.path
            }
        }
        
        sessions[sessionId] = AmphitheatreExportSession(registrar: self.registrar, task: task)
        return sessionId
    }
    
    public func awaitCropVideo(args: SessionArgs) async throws(FlutterError) -> String {
        do {
            let session = sessions[args.sessionId]
            if session == nil {
                throw FlutterError(code: "UNKNOWN_SESSION", message: "Invalid session ID.", details: args.sessionId)
            }
            
            return try await session!.task.value
        }  catch let error as FlutterError {
            throw error
        } catch {
            throw FlutterError(code: "UNEXPECTED_ERROR", message: "An unknown error has occurred.", details: nil)
        }
    }
    
    private func handleCropVideoProgress(sessionId: String, args: CropVideoArgs, progress: Double) {
        DispatchQueue.main.async {
            self.sessions[sessionId]?.notify(status: [
                "sessionId": sessionId,
                "stage": "export",
                "quality": args.quality.rawValue,
                "progress": progress,
            ])
        }
    }

}
