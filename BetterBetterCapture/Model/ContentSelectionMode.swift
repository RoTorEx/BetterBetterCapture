//
//  ContentSelectionMode.swift
//  BetterBetterCapture
//
//  Created by Joshua Sattler on 28.03.26.
//

import Foundation

/// The mode for content selection: picking content via the system picker, or drawing a screen area
enum ContentSelectionMode: String {
    /// The `UserDefaults` / `@AppStorage` key used to persist the selected mode.
    static let storageKey = "contentSelectionMode"

    /// The mode currently stored in `UserDefaults`, falling back to `.pickContent`.
    static var current: ContentSelectionMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey) else { return .pickContent }
        return ContentSelectionMode(rawValue: raw) ?? .pickContent
    }

    case pickContent
    case selectArea

    var label: String {
        switch self {
        case .pickContent: "Pick Content"
        case .selectArea: "Select Area"
        }
    }

    var icon: String {
        switch self {
        case .pickContent: "macwindow"
        case .selectArea: "rectangle.dashed"
        }
    }
}

/// The high-level recording mode shown directly under the Start Recording button.
/// - `audio`: captures system and/or microphone audio without any video content selection.
/// - `screenAndAudio`: captures screen content together with audio.
enum RecordingMode: String, CaseIterable, Identifiable {
    case audio
    case screenAndAudio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .audio:
            "Audio"
        case .screenAndAudio:
            "Screen + Audio"
        }
    }

    var icon: String {
        switch self {
        case .audio:
            "waveform"
        case .screenAndAudio:
            "display"
        }
    }
}
