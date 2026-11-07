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

@MainActor
public class AmphitheatreExportSession {
    /// The `FlutterPluginRegistrar` (i.e., Flutter app) that started the export session.
    let registrar: FlutterPluginRegistrar
    /// The ID of the session.
    let id: String
    /// The arguments that the export session was started with.
    let args: AmphitheatrePlugin.CropVideoArgs
    /// The asynchronous `Task` that encapsulates the export session.
    let task: AmphitheatreExportTask
    /// The event sink for the export session - where progress updates should be delivered.
    var sink: FlutterEventSink?

    init(registrar: FlutterPluginRegistrar, id: String, args: AmphitheatrePlugin.CropVideoArgs, task: AmphitheatreExportTask) {
        self.registrar = registrar
        self.id = id
        self.args = args
        self.task = task
    }

    /// Bind the given `FlutterEventSink` to the export session.
    ///
    /// Once the event sink is bound, progress updates will be delivered to the event sink as they become available.
    public func bind(sink: @escaping FlutterEventSink) throws(FlutterError) {
        if self.sink != nil {
            throw FlutterError(code: "CONFLICTING_BIND", message: "tried to bind an event sink to a session that was already bound (\(id))", details: nil)
        }

        self.sink = sink
    }

    /// Deliver the status update to Flutter.
    public func notify(status: Any) {
        self.sink?(status)
    }

    /// End the event stream bound to the export session (if any).
    public func close() {
        self.sink?(FlutterEndOfEventStream)
    }

    /// Cancel the export session.
    public func cancel() {
        self.task.cancel()
    }
}

public class AmphitheatrePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let registrar: FlutterPluginRegistrar

    /// The in-flight export sessions, keyed by session ID.
    ///
    /// Confined to the main actor - every access must occur on it.
    @MainActor
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
        // The engine invokes plugin callbacks on the main thread.
        MainActor.assumeIsolated { cleanUp() }
    }

    // This is unfortunately required to work around a limitation in Flutter's
    // hot reload (there is no way to detect it in platform code).
    // https://github.com/flutter/flutter/issues/10437
    @MainActor
    public func cleanUp() {
        for (sessionId, session) in sessions {
            if session.registrar.isEqual(registrar) {
                NSLog("Cleaning up session: \(sessionId)")
                session.cancel()
                sessions.removeValue(forKey: sessionId)
            }
        }
    }

    public struct SessionArgs {
        let sessionId: String

        public static func parse(arguments: Any?) throws(FlutterError) -> SessionArgs {
            guard let rawArgs = arguments as? NSDictionary,
                  let sessionId = rawArgs["sessionId"] as? NSString as? String
            else {
                throw FlutterError(code: "INVALID_ARGS", message: "invalid arguments for stream", details: nil)
            }

            return SessionArgs(sessionId: sessionId)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if (arguments == nil) {
            return nil
        }

        // The platform channel invokes the stream handler on the main thread.
        return MainActor.assumeIsolated { () -> FlutterError? in
            do {
                let args = try SessionArgs.parse(arguments: arguments)

                switch sessions[args.sessionId] {
                    case .some(let session): try session.bind(sink: events)
                    // The session is discarded once awaited, so a subscription
                    // that arrives after a fast export concluded has nothing
                    // left to report: the stream simply ends.
                    case .none: events(FlutterEndOfEventStream)
                }

                return nil
            } catch let error as FlutterError {
                return error
            } catch let error {
                return FlutterError(code: "UNKNOWN_ERR", message: "unknown error", details: "error on listen")
            }
        }
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        if (arguments == nil) {
            return nil
        }

        // The platform channel invokes the stream handler on the main thread.
        return MainActor.assumeIsolated { () -> FlutterError? in
            do {
                let args = try SessionArgs.parse(arguments: arguments)
                cancelCropVideo(sessionId: args.sessionId)
                return nil
            } catch let error as FlutterError {
                return error
            } catch let error {
                return FlutterError(code: "UNKNOWN_ERR", message: "unknown error", details: "error on cancel")
            }
        }
    }

    @MainActor
    public func cancelCropVideo(sessionId: String) {
        let session = sessions.removeValue(forKey: sessionId)
        if session == nil {
            // If the session was already gone, no need to do anything.
            return
        }

        session!.cancel()
    }

    @objc
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        Task.init { @MainActor in
            do {
                switch call.method {
                    case "_init":
                        self.cleanUp()
                        result(true)
                    case "getTemporaryDirectory": result(try await getTemporaryDirectory())
                    case "deleteFile": result(try await deleteFile(args: try DeleteFileArgs.parse(arguments: call.arguments)))
                    case "getAvailableDiskSpace": result(try await getAvailableDiskSpace())
                    case "checkCropVideoDiskSpace": result(try await checkCropVideoDiskSpace(args: try CropVideoArgs.parse(arguments: call.arguments)))
                    case "startCropVideo": result(try await startCropVideo(args: try CropVideoArgs.parse(arguments: call.arguments)))
                    case "awaitCropVideo": result(try await awaitCropVideo(args: try SessionArgs.parse(arguments: call.arguments)))
                    case "cancelCropVideo":
                        // Cancelling an unknown or already settled session is a no-op.
                        cancelCropVideo(sessionId: try SessionArgs.parse(arguments: call.arguments).sessionId)
                        result(nil)
                    case "getThumbnails": result(try await getThumbnails(args: try GetThumbnailsArgs.parse(arguments: call.arguments)))
                    default: result(FlutterMethodNotImplemented)
                }
            } catch is CancellationError {
                result(FlutterError(code: "EXPORT_CANCELLED", message: "the export session was cancelled", details: nil))
            } catch let error as FlutterError {
                result(error)
            } catch {
                result(FlutterError(code: "UNKNOWN_ERR", message: "unknown error", details: nil))
            }
        }

    }

    public struct DeleteFileArgs {
        let path: String

        public static func parse(arguments: Any?) throws(FlutterError) -> DeleteFileArgs {
            guard let rawArgs = arguments as? NSDictionary,
                  let path = rawArgs["path"] as? NSString as? String
            else {
                throw FlutterError(code: "INVALID_ARGS", message: "invalid arguments for deleteFile", details: nil)
            }

            if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FlutterError(code: "INVALID_PATH", message: "invalid path specified for deleteFile", details: nil)
            }

            return DeleteFileArgs(path: path)
        }
    }

    private func deleteFile(args: DeleteFileArgs) throws(FlutterError) -> Void? {
        do {
            try FileManager.default.removeItem(atPath: args.path)
            return nil
        } catch {
            throw FlutterError(code: "FILE_REMOVAL_FAILED", message: "failed to delete file at path", details: args.path)
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
        } catch {
            // Given withIntermediateDirectories is true, this will
            // not error if the directory already exists.
            throw FlutterError(code: "TEMPORARY_DIRECTORY", message: "failed to create a package-specific temporary directory", details: nil)
        }

        // Return the path to the directory, on success.
        return path
    }

    private func getAvailableDiskSpace() throws(FlutterError) -> Int64 {
        let resourceValues = try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        
        guard let availableBytes = resourceValues?.volumeAvailableCapacityForImportantUsage else {
            throw FlutterError(code: "PRECONDITION_FAIL", message: "the available disk space could not be determined", details: nil)
        }
        
        return availableBytes
    }

    public enum CropVideoQuality: String {
        case presetHD = "presetHD"
        case presetFullHD = "presetFullHD"
        case highest = "highest"
        case passthrough = "passthrough"

        static let defaultQuality: CropVideoQuality = CropVideoQuality.passthrough

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
              throw FlutterError(code: "INVALID_ARGS", message: "invalid arguments for cropVideo", details: nil)
            }

            guard start <= end else {
                throw FlutterError(code: "INVALID_ARGS", message: "invalid arguments for cropVideo: 'start' must not be after 'end'", details: nil)
            }

            return CropVideoArgs(path: path, start: start, end: end, quality: quality)
        }
    }

    @MainActor
    private func getNewSessionId() -> String {
        var sessionId: String? = nil

        while (sessionId == nil || sessions.keys.contains(sessionId!)) {
            sessionId = UUID().uuidString
        }

        return sessionId!
    }

    /// Check that the device has enough free disk space to hold the output
    /// of the given crop operation.
    ///
    /// The output size is estimated by scaling the input file's size by the
    /// proportion of the video that the crop keeps. Throws
    /// `EXCEEDS_DISK_SPACE` if the estimate exceeds the free space available
    /// on the volume holding the plugin's temporary directory (where the
    /// output is written), and `PRECONDITION_FAIL` if the estimate cannot be
    /// computed.
    public func checkCropVideoDiskSpace(args: CropVideoArgs) async throws(FlutterError) -> Void? {
        do {
            // Ensure the specified path exists and is not a directory.
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: args.path, isDirectory: &isDirectory) {
                throw FlutterError(code: "SEARCH_FAIL", message: "failed to locate the provided file path", details: nil)
            }

            if isDirectory.boolValue {
                throw FlutterError(code: "INVALID_FILE_PATH", message: "the provided file path is a directory", details: args.path)
            }

            // Measure the size of the input file.
            let attributes = try FileManager.default.attributesOfItem(atPath: args.path)
            guard let fileSize = (attributes[.size] as? NSNumber)?.uint64Value else {
                throw FlutterError(code: "PRECONDITION_FAIL", message: "the size of the video could not be determined", details: args.path)
            }

            // Measure the duration of the video, in milliseconds.
            let url: URL
            if #available(iOS 16.0, *) {
                url = URL.init(filePath: args.path, directoryHint: URL.DirectoryHint.notDirectory)
            } else {
                url = URL(fileURLWithPath: args.path, isDirectory: false)
            }

            let durationSeconds: Double
            if #available(iOS 15.0, *) {
                durationSeconds = try await AVURLAsset(url: url).load(.duration).seconds
            } else {
                durationSeconds = AVURLAsset(url: url).duration.seconds
            }

            let durationMs = durationSeconds.isFinite && durationSeconds > 0 ? UInt64((durationSeconds * 1000).rounded()) : 0
            guard durationMs > 0 else {
                throw FlutterError(code: "PRECONDITION_FAIL", message: "the duration of the video could not be determined", details: args.path)
            }

            // Estimate the output size by scaling the input file's size by
            // the proportion of the video that the crop keeps. The crop
            // range is clamped to the video's duration.
            let cropMs = min(args.end - args.start, durationMs)
            let requiredBytes = UInt64((Double(fileSize) * (Double(cropMs) / Double(durationMs))).rounded(.up))

            // Measure the free space available on the volume that will hold
            // the output (the plugin's temporary directory).
            let availableBytes = try getAvailableDiskSpace()

            if requiredBytes > UInt64(clamping: availableBytes) {
                throw FlutterError(code: "EXCEEDS_DISK_SPACE", message: "There is not enough free space on this device to process the video.", details: [
                    "requiredBytes": Int64(clamping: requiredBytes),
                    "availableBytes": availableBytes,
                ])
            }
            
            return nil
        } catch let error as FlutterError {
            throw error
        } catch {
            throw FlutterError(code: "PRECONDITION_FAIL", message: "failed to determine whether there is sufficient disk space", details: nil)
        }
    }

    @MainActor
    public func startCropVideo(args: CropVideoArgs) async throws(FlutterError) -> String {
        let sessionId = getNewSessionId()

        // Ensure the specified path exists and is not a directory.
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: args.path, isDirectory: &isDirectory) {
            throw FlutterError(code: "SEARCH_FAIL", message: "failed to locate the provided file path", details: nil)
        }

        if isDirectory.boolValue {
            throw FlutterError(code: "INVALID_FILE_PATH", message: "the provided file path is a directory", details: args.path)
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

        // The output is a session-unique file in the plugin's temporary
        // directory - the input may not be in a writable location (e.g., a
        // file picked from the photo gallery).
        let temporaryDirectory = try getTemporaryDirectory()
        let outUrl: URL
        if #available(iOS 16.0, *) {
            outUrl = URL(filePath: temporaryDirectory, directoryHint: URL.DirectoryHint.isDirectory)
                .appending(path: "\(sessionId).mp4", directoryHint: URL.DirectoryHint.notDirectory)
        } else {
            outUrl = URL(fileURLWithPath: temporaryDirectory, isDirectory: true)
                .appendingPathComponent("\(sessionId).mp4", isDirectory: false)
        }

        // Attempt to remove any existing file at outUrl.
        _ = try? FileManager.default.removeItem(at: outUrl)

        // Configure the export session.
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: args.quality.asExportPreset()) else {
            throw FlutterError(code: "FAILED_TO_CREATE_EXPORT_SESSION", message: "failed to initialize an export session", details: nil)
        }

        exportSession.timeRange = timeRange

        // TODO(SamJakob): make this configurable
        exportSession.shouldOptimizeForNetworkUse = false

        // Start the file export.
        let task = AmphitheatreExportTask {
            if #available(iOS 18, *) {
                async let export: () = exportSession.export(to: outUrl, as: AVFileType.mp4)

                for await state in exportSession.states(updateInterval: 0.1) {
                    if case .exporting(let progress) = state {
                        if let session = self.sessions[sessionId] {
                            self.handleCropVideoProgress(session: session, progress: progress.fractionCompleted)
                        }
                    }
                }

                do {
                    try await export
                } catch let error {
                    // Remove any partial output before failing.
                    _ = try? FileManager.default.removeItem(at: outUrl)

                    if error is CancellationError {
                        throw FlutterError(code: "EXPORT_CANCELLED", message: "the export session was cancelled", details: error.localizedDescription)
                    }

                    throw FlutterError(code: "EXPORT_FAILED", message: "an error occurred during the export session", details: error.localizedDescription)
                }
            } else {

                exportSession.outputURL = outUrl
                exportSession.outputFileType = AVFileType.mp4

                // The legacy export() exposes no progress stream, so it is
                // polled. The timer retains the session and self, so it is
                // stopped on every exit from this block (completion, failure,
                // or a cancellation that prevents the export from starting);
                // the timer never invalidates itself.
                let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    // The timer fires on the main run loop.
                    MainActor.assumeIsolated {
                        if let session = self.sessions[sessionId] {
                            self.handleCropVideoProgress(session: session, progress: Double(exportSession.progress))
                        }
                    }
                }
                defer { progressTimer.invalidate() }

                // Swift cancellation is cooperative and the legacy export()
                // does not observe it, so the handler stops the session. A task
                // cancelled before this point never starts the export.
                try Task.checkCancellation()
                await withTaskCancellationHandler {
                    await exportSession.export()
                } onCancel: {
                    exportSession.cancelExport()
                }

                switch exportSession.status {
                case .completed:
                    break
                case .failed:
                    _ = try? FileManager.default.removeItem(at: outUrl)
                    throw FlutterError(code: "EXPORT_FAILED", message: "an error occurred during the export session", details: exportSession.error?.localizedDescription)
                case .cancelled:
                    _ = try? FileManager.default.removeItem(at: outUrl)
                    throw FlutterError(code: "EXPORT_CANCELLED", message: "the export session was cancelled", details: nil)
                case .unknown: fallthrough
                case .waiting: fallthrough
                case .exporting:
                    _ = try? FileManager.default.removeItem(at: outUrl)
                    throw FlutterError(code: "EXPORT_STATE_INVALID", message: "the export session ended in an illegal state ('\(exportSession.status)')", details: nil)
                }
            }

            if #available(iOS 16.0, *) {
                return outUrl.path()
            } else {
                return outUrl.path
            }
        }

        sessions[sessionId] = AmphitheatreExportSession(registrar: self.registrar, id: sessionId, args: args, task: task)
        return sessionId
    }

    @MainActor
    public func awaitCropVideo(args: SessionArgs) async throws(FlutterError) -> String {
        do {
            let session = sessions[args.sessionId]
            if session == nil {
                throw FlutterError(code: "UNKNOWN_SESSION", message: "invalid session ID", details: args.sessionId)
            }

            // The session is discarded once its export has concluded.
            defer { sessions.removeValue(forKey: args.sessionId) }

            let path = try await session!.task.value

            // On success, ensure 100% is reported and end the event stream.
            handleCropVideoProgress(session: session!, progress: 1.0)
            session!.close()

            return path
        } catch let error as FlutterError {
            throw error
        } catch is CancellationError {
            throw FlutterError(code: "EXPORT_CANCELLED", message: "the export session was cancelled", details: nil)
        } catch {
            throw FlutterError(code: "UNEXPECTED_ERROR", message: "an unknown error has occurred", details: nil)
        }
    }

    public struct GetThumbnailsArgs {
        /// No more than this many frames are extracted, however many are asked for.
        static let maxCount = 50

        /// Frames are never taller than this, however tall a frame is asked for.
        static let maxHeightLimit = 1080

        let path: String
        let count: Int
        let maxHeight: Int

        public static func parse(arguments: Any?) throws(FlutterError) -> GetThumbnailsArgs {
            guard let rawArgs = arguments as? NSDictionary,
                  let path = rawArgs["path"] as? NSString as? String,
                  let count = (rawArgs["count"] as? NSNumber)?.intValue,
                  let maxHeight = (rawArgs["maxHeight"] as? NSNumber)?.intValue
            else {
                throw FlutterError(code: "INVALID_ARGS", message: "invalid arguments for getThumbnails", details: nil)
            }

            guard count >= 1, maxHeight >= 1 else {
                throw FlutterError(code: "INVALID_ARGS", message: "invalid arguments for getThumbnails: 'count' and 'maxHeight' must be positive", details: nil)
            }

            return GetThumbnailsArgs(path: path, count: min(count, maxCount), maxHeight: min(maxHeight, maxHeightLimit))
        }
    }

    /// Extract evenly spaced JPEG thumbnails of the video for the editor's
    /// filmstrip (sampled at the midpoint of each cell, so the first and last
    /// frames are representative), each at most `maxHeight` pixels tall.
    ///
    /// Frames that fail to decode are skipped and an unreadable video yields
    /// an empty list: the filmstrip is an enhancement, never an error.
    @MainActor
    private func getThumbnails(args: GetThumbnailsArgs) async throws(FlutterError) -> [FlutterStandardTypedData] {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: args.path, isDirectory: &isDirectory) {
            throw FlutterError(code: "SEARCH_FAIL", message: "failed to locate the provided file path", details: nil)
        }

        if isDirectory.boolValue {
            throw FlutterError(code: "INVALID_FILE_PATH", message: "the provided file path is a directory", details: args.path)
        }

        let url: URL
        if #available(iOS 16.0, *) {
            url = URL.init(filePath: args.path, directoryHint: URL.DirectoryHint.notDirectory)
        } else {
            url = URL(fileURLWithPath: args.path, isDirectory: false)
        }

        let count = args.count
        let maxHeight = args.maxHeight

        // Decoding runs off the main actor; only the encoded bytes come back.
        let encoded: [Data] = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            let duration: CMTime
            if #available(iOS 15, *) {
                duration = (try? await asset.load(.duration)) ?? .zero
            } else {
                duration = asset.duration
            }

            // An unreadable or indefinite duration would produce invalid
            // times; there are no thumbnails to extract.
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else {
                return []
            }

            // AVFoundation only documents CGSizeZero as "unscaled", not a
            // single zero component, so both components of maximumSize are
            // given explicitly. The width is derived from the aspect ratio
            // of the track as displayed (naturalSize after the preferred
            // transform, which the generator also applies). Without a video
            // track there are no frames to extract.
            let naturalSize: CGSize
            let preferredTransform: CGAffineTransform
            if #available(iOS 15, *) {
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let properties = try? await track.load(.naturalSize, .preferredTransform)
                else {
                    return []
                }
                naturalSize = properties.0
                preferredTransform = properties.1
            } else {
                guard let track = asset.tracks(withMediaType: .video).first else {
                    return []
                }
                naturalSize = track.naturalSize
                preferredTransform = track.preferredTransform
            }

            let displaySize = naturalSize.applying(preferredTransform)
            let displayWidth = abs(displaySize.width)
            let displayHeight = abs(displaySize.height)
            guard displayWidth > 0, displayHeight > 0 else {
                return []
            }

            let maxWidth = max(1, ceil(CGFloat(maxHeight) * displayWidth / displayHeight))
            generator.maximumSize = CGSize(width: maxWidth, height: CGFloat(maxHeight))

            let times: [CMTime] = (0..<count).map { index in
                CMTime(
                    seconds: seconds * (2.0 * Double(index) + 1.0) / (2.0 * Double(count)),
                    preferredTimescale: 600)
            }

            var thumbnails: [Data] = []

            if #available(iOS 16, *) {
                for await imageResult in generator.images(for: times) {
                    if let cgImage = try? imageResult.image,
                       let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) {
                        thumbnails.append(jpeg)
                    }
                }
            } else {
                for time in times {
                    if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil),
                       let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) {
                        thumbnails.append(jpeg)
                    }
                }
            }

            return thumbnails
        }.value

        return encoded.map { FlutterStandardTypedData(bytes: $0) }
    }

    /// Deliver a progress update for the given session to Flutter.
    @MainActor
    private func handleCropVideoProgress(session: AmphitheatreExportSession, progress: Double) {
        session.notify(status: [
            "sessionId": session.id,
            "stage": "export",
            "quality": session.args.quality.rawValue,
            "progress": progress,
        ])
    }

}
