import Flutter
import UIKit
import AVFoundation

let PLUGIN_BUNDLE_ID = "xyz.apollosoftware.amphitheatre"

public class AmphitheatrePlugin: NSObject, FlutterPlugin {
    @objc
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: PLUGIN_BUNDLE_ID, binaryMessenger: registrar.messenger())
        let instance = AmphitheatrePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    @objc
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getTemporaryDirectory":
            
            let cachesDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
            
            if (cachesDirectory.isEmpty) {
                result(FlutterError(code: "ERR_SEARCH_FAIL", message: "Failed to locate the user temporary directory.", details: nil))
                return
            }
            
            let url: URL
            let path: String
            if #available(iOS 16.0, *) {
                url = URL.init(filePath: cachesDirectory.first!, directoryHint: URL.DirectoryHint.isDirectory).appending(path: PLUGIN_BUNDLE_ID + "/")
                path = url.path(percentEncoded: false)
            } else {
                url = URL(fileURLWithPath: cachesDirectory.first!, isDirectory: true).appendingPathComponent(PLUGIN_BUNDLE_ID)
                path = url.path
            }
            
            var isDirectory: ObjCBool = true
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                if (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) == nil {
                    result(FlutterError(code: "ERR_INIT_FAIL", message: "Failed to create the package-specific temporary directory.", details: nil))
                    return
                }
            }
        
            result(path)
        case "cropVideo":
            if let (path, start, end) = try? parseCropVideoArgs(arguments: call.arguments) {
                
                var isDirectory: ObjCBool = false
                if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
                    result(FlutterError(code: "ERR_SEARCH_FAIL", message: "Failed to locate the provided file path.", details: nil))
                    return
                }
                
                let url: URL
                if #available(iOS 16.0, *) {
                    url = URL.init(filePath: path, directoryHint: URL.DirectoryHint.notDirectory)
                } else {
                    url = URL(fileURLWithPath: path, isDirectory: false)
                }
                
                let asset: AVURLAsset = AVURLAsset.init(url: url)
                Task.init {
                    let outUrl: URL
                    
                    do {
                        outUrl = try await cropVideo(asset: asset, start: start, end: end)
                    } catch {
                        result(FlutterError(code: "ERR_FAIL", message: "The operation failed.", details: nil))
                        return
                    }
                    
                    // Attempt to remove the old file. If the remove fails, do nothing
                    // as the OS should automatically clean it up when it wants to.
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {}
                    
                    if #available(iOS 16.0, *) {
                        result(outUrl.path())
                    } else {
                        result(outUrl.path)
                    }
                }
            } else {
                result(FlutterError(code: "ERR_BAD_PARAMS", message: "Invalid parameters supplied to cropVideo()", details: nil))
                return
            }
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func parseCropVideoArgs(arguments: Any) throws -> (path: String, start: UInt64, end: UInt64) {
        let path: String
        let start: UInt64
        let end: UInt64
        
        guard let rawArgs = arguments as? NSDictionary,
              let path = (rawArgs["path"] as? NSString) as? String,
              let start = (rawArgs["start"] as? NSNumber)?.uint64Value,
              let end = (rawArgs["end"] as? NSNumber)?.uint64Value
        else { throw NSError(domain: PLUGIN_BUNDLE_ID, code: NSBundleErrorMinimum) }
        
        return (path, start, end)
    }
    
    private func cropVideo(asset: AVURLAsset, start: UInt64, end: UInt64) async throws -> URL {
        let duration: CMTime
        if #available(iOS 15, *) {
            duration = try await asset.load(.duration)
        } else {
            duration = asset.duration
        }
        
        // Define the time range to crop the video to.
        let startTime = CMTime(seconds: Double(start)/1000, preferredTimescale: 1000)
        let endTime = CMTime(seconds: Double(end)/1000, preferredTimescale: 1000)
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
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: PLUGIN_BUNDLE_ID, code: NSBundleErrorMinimum)
        }
        
        // Configure the export session.
        exportSession.timeRange = timeRange
        
        // Export the file.
        if #available(iOS 18, *) {
            try await exportSession.export(to: outUrl, as: AVFileType.mp4)
        } else {
            exportSession.outputURL = outUrl
            exportSession.outputFileType = AVFileType.mp4
            await exportSession.export()
        }
        
        switch exportSession.status {
        case .completed:
            return outUrl
        case .failed: fallthrough
        case .cancelled:
            throw NSError(domain: PLUGIN_BUNDLE_ID, code: NSBundleErrorMinimum, userInfo: ["error": exportSession.error])
        case .unknown: fallthrough
        case .waiting: fallthrough
        case .exporting:
            throw NSError(domain: PLUGIN_BUNDLE_ID, code: NSBundleErrorMinimum, userInfo: ["error": "The export ended in an illegal state."])
        }
    }

}
