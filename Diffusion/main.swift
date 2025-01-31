// bomberfish
// main.swift – Diffusion
// created on 2024-12-22

import Foundation
import SwiftUICore

let runningOnMac = ProcessInfo.processInfo.isMacCatalystApp
let deviceHas6GBOrMore = ProcessInfo.processInfo.physicalMemory > 5910000000   // Reported by iOS 17 beta (21A5319a) on iPhone 13 Pro: 5917753344
let deviceHas8GBOrMore = ProcessInfo.processInfo.physicalMemory > 7900000000   // Reported by iOS 17.0.2 on iPhone 15 Pro Max: 8021032960

let deviceSupportsQuantization = {
    if #available(iOS 17, *) {
        true
    } else {
        false
    }
}()

var intelligenceIcon: String {
    if #available(iOS 18, *) {
        "apple.intelligence"
    } else {
        "sparkles"
    }
}

let intelligenceColors: [Color] = [
    .init(hex: "FF9004"),
    .init(hex: "FF2E54"),
    .init(hex: "C959DD"),
    .init(hex: "0894FF")
]


print("Device has \(ProcessInfo.processInfo.physicalMemory) bytes of RAM")

DiffusionApp.main()
