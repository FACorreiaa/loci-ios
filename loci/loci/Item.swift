//
//  Item.swift
//  loci
//
//  Created by Fernando Correia Chill on 18/09/2026.
//

import Foundation
import SwiftData

@Model final class Item {
  var timestamp: Date

  init(timestamp: Date) { self.timestamp = timestamp }
}
