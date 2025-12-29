//
//  AboutSettingsView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 27/12/25.
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 16) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .frame(width: 96, height: 96)
                    .cornerRadius(16)

                VStack(spacing: 4) {
                    Text("MonkeyNote")
                        .font(.system(size: 24, weight: .bold))
                    Text("Version \(AppConfig.version) ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 12) {
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/cavaldos/MonkeyNote")!)
                }) {
                    Text("Contribute")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .frame(width: 150)

                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://github.com/cavaldos/MonkeyNote/issues")!)
                }) {
                    Text("Report a Bug")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .frame(width: 150)

                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/calvados")!)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                        Text("Support me")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .frame(width: 150)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
        }
    }
}
