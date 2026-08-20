//
//  AudioTrackMixer.swift
//  BetterBetterCapture
//

import AVFoundation
import Foundation

/// Replaces separate system and microphone tracks with one broadly compatible mixed track.
enum AudioTrackMixer {
    static func mixTracks(
        in sourceURL: URL,
        codec: AudioCodec,
        bitrate: AudioBitrate
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1 else { return }

        let temporaryURL = sourceURL
            .deletingLastPathComponent()
            .appending(path: ".\(UUID().uuidString)-mixed.\(sourceURL.pathExtension)")

        do {
            try await writeMixedTrack(
                from: asset,
                audioTracks: audioTracks,
                to: temporaryURL,
                codec: codec,
                bitrate: bitrate
            )
            _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    private static func writeMixedTrack(
        from asset: AVAsset,
        audioTracks: [AVAssetTrack],
        to outputURL: URL,
        codec: AudioCodec,
        bitrate: AudioBitrate
    ) async throws {
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0.5, at: .zero)
            return parameters
        }
        readerOutput.audioMix = audioMix

        guard reader.canAdd(readerOutput) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(
            outputURL: outputURL,
            fileType: codec == .aac ? .mp4 : .wav
        )
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings(codec: codec, bitrate: bitrate)
        )

        guard writer.canAdd(writerInput) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        guard reader.startReading() else {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        writer.startSession(atSourceTime: .zero)

        while reader.status == .reading {
            guard writerInput.isReadyForMoreMediaData else {
                try await Task.sleep(for: .milliseconds(2))
                continue
            }

            guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                break
            }
            guard writerInput.append(sampleBuffer) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }

        if reader.status == .failed {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        guard writer.status == .completed else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    private static func outputSettings(codec: AudioCodec, bitrate: AudioBitrate) -> [String: Any] {
        switch codec {
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: bitrate.rawValue,
            ]
        case .pcm:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }
    }
}
