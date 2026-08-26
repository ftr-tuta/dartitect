import AppTrackingTransparency
import Flutter
import UIKit

public final class DartitectPrivacyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.dartitect/privacy",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(DartitectPrivacyPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result(currentStatus())
    case "request":
      guard #available(iOS 14, *) else {
        result("notSupported")
        return
      }
      DispatchQueue.main.async {
        ATTrackingManager.requestTrackingAuthorization { status in
          DispatchQueue.main.async { result(self.map(status)) }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func currentStatus() -> String {
    guard #available(iOS 14, *) else { return "notSupported" }
    return map(ATTrackingManager.trackingAuthorizationStatus)
  }

  @available(iOS 14, *)
  private func map(_ status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    @unknown default: return "notSupported"
    }
  }
}
