//
//  AppConfig.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 08/01/26.
//

import Foundation

enum AppConfig {
    // Release CI injects MARKETING_VERSION / CURRENT_PROJECT_VERSION from the
    // git tag, so read them from the bundle instead of hardcoding.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.4"
    }
    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "1"
    }

    static let appName = "MonkeyNote"
    static let bundleIdentifier = "com.monkeynote.app"
}
