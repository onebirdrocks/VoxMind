//
//  OBVoiceLabApp.swift
//  OBVoiceLab
//
//  Created by Ruan Yiming on 2025/6/22.
//

import SwiftUI
import SwiftData

@main
struct VoxMindLabApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: VoiceLog.self)
    }
}
