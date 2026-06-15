import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let storageChannelName = "edenproject/app_storage"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerStorageChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerStorageChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: storageChannelName,
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getEdenGalleryStorageDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }

      do {
        let supportDirectory = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )
        let galleryDirectory = supportDirectory.appendingPathComponent(
          "eden_gallery",
          isDirectory: true
        )
        try FileManager.default.createDirectory(
          at: galleryDirectory,
          withIntermediateDirectories: true
        )
        result(galleryDirectory.path)
      } catch {
        result(
          FlutterError(
            code: "storage_unavailable",
            message: "Unable to create eden gallery storage directory.",
            details: "\(error)"
          )
        )
      }
    }
  }
}
