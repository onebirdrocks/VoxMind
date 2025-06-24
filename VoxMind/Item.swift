//
//  Item.swift
//  OBVoiceLab
//
//  Created by Ruan Yiming on 2025/6/22.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
