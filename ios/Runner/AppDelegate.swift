import UIKit
import Flutter
import HealthKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let healthChannel = FlutterMethodChannel(name: "health_channel",
                                              binaryMessenger: controller.binaryMessenger)
    
    healthChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      switch call.method {
      case "requestPermissions":
        // Simulate HealthKit permission
        result(true)
      case "getSteps":
        // Simulate HealthKit steps
        result(8742)
      case "getSleepData":
        result(8.2)
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
