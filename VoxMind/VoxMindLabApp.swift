import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct VoxMindLabApp: App {
    @State private var spotlightVoiceLogID: String? = nil
    
    var body: some Scene {
        WindowGroup {
            ContentView(spotlightVoiceLogID: $spotlightVoiceLogID)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let userInfo = activity.userInfo,
                          let id = userInfo[CSSearchableItemActivityIdentifier] as? String else {
                        return
                    }
                    spotlightVoiceLogID = id
                }
        }
        .modelContainer(for: [
            VoiceLog.self,
            CachedLifelog.self,
            DateLoadStatus.self
        ])
        
    }
}

