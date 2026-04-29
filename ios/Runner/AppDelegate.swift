import UIKit
import Flutter
import HealthKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    if let controller = window?.rootViewController as? FlutterViewController {
      let healthChannel = FlutterMethodChannel(name: "health_channel",
                                                binaryMessenger: controller.binaryMessenger)
      
      healthChannel.setMethodCallHandler({
        (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        switch call.method {
        case "requestPermissions":
          result(true)
        case "getSteps":
          result(8742)
        case "getSleepData":
          result(8.2)
        default:
          result(FlutterMethodNotImplemented)
        }
      })
    }
    
    return result
  }
}
