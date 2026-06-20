//
//  AppDelegate.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import UIKit

/// Application launch hook. Intentionally minimal — HeicSwap configures no
/// third-party SDKs at launch (privacy-first: nothing that phones home).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}
