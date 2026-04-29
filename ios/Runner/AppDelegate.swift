import UIKit
import Flutter
import HealthKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Workmanager setup for iOS
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
    }
    
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    // Robustly initialize health channel
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
