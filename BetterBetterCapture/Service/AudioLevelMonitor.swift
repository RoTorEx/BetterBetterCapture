import AVFoundation
import CoreAudio
import Foundation
import OSLog

// MARK: - Audio Level Monitor

/// Computes audio levels from CMSampleBuffer PCM samples and publishes
/// smoothed 0...1 levels for system audio and microphone sources.
@MainActor
@Observable
final class AudioLevelMonitor {
    private(set) var systemAudioLevel: CGFloat = 0
    private(set) var microphoneLevel: CGFloat = 0

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetterBetterCapture",
        category: "AudioLevelMonitor"
    )
    nonisolated(unsafe) private static var lastLogDate = Date.distantPast
    nonisolated private static let logInterval: TimeInterval = 1.0

    nonisolated func processSystemAudioSample(_ sampleBuffer: CMSampleBuffer) {
        let level = Self.computeLevel(from: sampleBuffer)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.systemAudioLevel = Self.smooth(current: self.systemAudioLevel, target: level)
        }
    }

    nonisolated func processMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
        let level = Self.computeLevel(from: sampleBuffer)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.microphoneLevel = Self.smooth(current: self.microphoneLevel, target: level)
        }
    }

    nonisolated private static func smooth(current: CGFloat, target: CGFloat) -> CGFloat {
        let attack: CGFloat = 0.6
        let decay: CGFloat = 0.8

        if target > current {
            return current * (1 - attack) + target * attack
        } else {
            return max(current * decay, 0)
        }
    }

    nonisolated private static func computeLevel(from sampleBuffer: CMSampleBuffer) -> CGFloat {
        guard let statistics = AudioSampleBufferProcessor.statistics(from: sampleBuffer),
              statistics.sampleCount > 0 else {
            return 0
        }

        let rms = sqrt(statistics.sumOfSquares / Double(statistics.sampleCount))
        let level = levelFromDecibels(rms: rms)

        let now = Date()
        if now.timeIntervalSince(Self.lastLogDate) >= Self.logInterval {
            Self.lastLogDate = now
            Self.logger.debug(
                "Audio level debug — samples=\(statistics.sampleCount), rms=\(rms), level=\(level)"
            )
        }

        return CGFloat(level)
    }

    /// Converts an RMS value to a perceptual 0...1 level using a dB scale with a noise floor.
    /// Uses a -40 dB floor and a square-root curve so low-level noise is visually suppressed.
    nonisolated private static func levelFromDecibels(rms: Double) -> Double {
        let minDb: Double = -40
        let maxDb: Double = 0

        // Hard silence gate: anything below -45 dB is treated as absolute silence.
        let silenceThreshold: Double = 0.0056 // -45 dB
        if rms < silenceThreshold {
            return 0
        }

        // Avoid log10(0)
        let decibels = 20 * log10(max(rms, 0.0000001))
        let clampedDb = min(max(decibels, minDb), maxDb)
        let linear = (clampedDb - minDb) / (maxDb - minDb)
        // Square-root curve suppresses low-level noise visually.
        return sqrt(linear)
    }

    nonisolated static func defaultOutputDeviceName() -> String {
        defaultDeviceName(selector: kAudioHardwarePropertyDefaultOutputDevice, fallback: "System Audio")
    }

    nonisolated static func defaultInputDeviceName() -> String {
        defaultDeviceName(selector: kAudioHardwarePropertyDefaultInputDevice, fallback: "System Microphone")
    }

    nonisolated private static func defaultDeviceName(selector: AudioObjectPropertySelector, fallback: String) -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr else { return fallback }

        var namePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let nameStatus = AudioObjectGetPropertyData(
            deviceID,
            &namePropertyAddress,
            0,
            nil,
            &nameSize,
            &unmanagedName
        )

        guard nameStatus == noErr, let cfName = unmanagedName?.takeUnretainedValue() else {
            return fallback
        }

        return cfName as String
    }

    /// Resets published audio levels to zero, called when recording stops.
    func resetLevels() {
        systemAudioLevel = 0
        microphoneLevel = 0
    }

    /// Reads the current scalar volume (0...1) of the default output device, if available.
    nonisolated static func defaultOutputVolume() -> Float? {
        defaultDeviceVolume(selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeOutput)
    }

    /// Reads the current scalar volume (0...1) of the default input device, if available.
    nonisolated static func defaultInputVolume() -> Float? {
        defaultDeviceVolume(selector: kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeInput)
    }

    nonisolated private static func defaultDeviceVolume(selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> Float? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr else { return nil }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume: Float = 0
        var volumeSize = UInt32(MemoryLayout<Float>.size)

        let volumeStatus = AudioObjectGetPropertyData(
            deviceID,
            &volumeAddress,
            0,
            nil,
            &volumeSize,
            &volume
        )

        guard volumeStatus == noErr else { return nil }
        return volume
    }
}
