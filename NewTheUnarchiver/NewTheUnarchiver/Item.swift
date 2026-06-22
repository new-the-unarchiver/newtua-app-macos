//
//  Item.swift
//  NewTheUnarchiver
//
//  Created by Aleksei Trankov on 22.06.2026.
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
