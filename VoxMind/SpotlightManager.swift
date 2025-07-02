

import Foundation
import CoreSpotlight
import MobileCoreServices

class SpotlightManager {
    static let shared = SpotlightManager()
    

    func insertVoiceLog(vlog: VoiceLog) {
        let attributeSet = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)

        attributeSet.title = vlog.title
        attributeSet.contentDescription = vlog.translatedSummary
        attributeSet.keywords = ["note", "语音笔记", vlog.title]

        let item = CSSearchableItem(
            uniqueIdentifier: vlog.id.uuidString,
            domainIdentifier: "app.voxmind.voicelog",
            attributeSet: attributeSet
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                print("❌ 索引失败：\(error.localizedDescription)")
            } else {
                print("✅ 索引成功：\(vlog.title)")
            }
        }
    }
    
    func updateVoiceLog(vlog: VoiceLog){
        insertVoiceLog(vlog:vlog)
    }

    func deleteVoiceLog(vLogID: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [vLogID]) { error in
            if let error = error {
                print("❌ 删除 Spotlight 索引失败：\(error.localizedDescription)")
            } else {
                print("🗑️ 已删除 Spotlight 索引：\(vLogID)")
            }
        }
    }
}

