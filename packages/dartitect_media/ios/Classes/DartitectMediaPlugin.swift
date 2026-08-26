import Flutter
import Photos
import UIKit

public final class DartitectMediaPlugin: NSObject, FlutterPlugin {
  // Album lookup/creation requires read/write library access, so the 1.0
  // contract deliberately uses readWrite for status, request, and save.
  private let accessLevel: PHAccessLevel = .readWrite

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.dartitect/media", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(DartitectMediaPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status": result(map(PHPhotoLibrary.authorizationStatus(for: accessLevel)))
    case "request":
      PHPhotoLibrary.requestAuthorization(for: accessLevel) { status in
        DispatchQueue.main.async { result(self.map(status)) }
      }
    case "saveImage": saveImage(call, result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func map(_ status: PHAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted, .denied: return "denied"
    case .limited: return "limited"
    case .authorized: return "authorized"
    @unknown default: return "notSupported"
    }
  }

  private func saveImage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String else {
      result(FlutterError(code: "invalid_file", message: nil, details: nil)); return
    }
    let url = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      result(FlutterError(code: "file_not_found", message: nil, details: nil)); return
    }
    guard !isDirectory.boolValue, UIImage(contentsOfFile: path) != nil else {
      result(FlutterError(code: "invalid_file", message: nil, details: nil)); return
    }
    switch PHPhotoLibrary.authorizationStatus(for: accessLevel) {
    case .limited:
      result(FlutterError(code: "limited_access", message: nil, details: nil)); return
    case .authorized: break
    default:
      result(FlutterError(code: "permission_denied", message: nil, details: nil)); return
    }
    let albumName = arguments["album"] as? String
    var placeholder: PHObjectPlaceholder?
    PHPhotoLibrary.shared().performChanges({
      let creation = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
      placeholder = creation?.placeholderForCreatedAsset
      if let name = albumName, let asset = placeholder {
        let albumRequest = self.album(named: name).flatMap { PHAssetCollectionChangeRequest(for: $0) } ??
          PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
        albumRequest.addAssets([asset] as NSArray)
      }
    }) { success, _ in
      DispatchQueue.main.async {
        guard success, let identifier = placeholder?.localIdentifier else {
          result(FlutterError(code: "native_error", message: nil, details: nil)); return
        }
        result(["identifier": identifier])
      }
    }
  }

  private func album(named name: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title = %@", name)
    return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
  }
}
