import AVFoundation
import Foundation

/// Independently playable PCM chunks. Closed chunks survive even when the
/// capture container cannot be finalized after an interruption.
nonisolated final class AudioRecoveryJournal {
    let directory: URL
    private var sources: [String: Source] = [:]
    private let chunkDuration: Double = 2

    private struct Source {
        var file: FileHandle
        var url: URL
        var frames: Int = 0
    }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("""
        Interrupted recording recovery

        Each .caf file is a closed, lossless audio fragment playable by QuickTime.
        system and microphone are separate sources. The number in each filename
        is its starting offset in seconds from the recording's first sample.
        Files ending in .partial.caf were open at interruption and may be incomplete.
        The adjacent -unprocessed.mov contains the original capture when readable.
        These files are removed only after the final recording is installed successfully.
        """.utf8).write(to: directory.appending(path: "README.txt"), options: .atomic)
    }

    func append(_ sample: CMSampleBuffer, source: String, origin: CMTime) throws {
        guard let description = CMSampleBufferGetFormatDescription(sample) else {
            throw AudioPostProcessingError.cannotReadTrack
        }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0 else { return }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
            throw AudioPostProcessingError.cannotAllocateBuffer
        }
        pcm.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList)
        guard status == noErr else { throw AudioPostProcessingError.cannotReadTrack }

        if sources[source] == nil {
            let offset = max(0, (CMSampleBufferGetPresentationTimeStamp(sample) - origin).seconds)
            let name = source + "-" + offset.formatted(.number.grouping(.never).precision(.fractionLength(3)).locale(Locale(identifier: "en_US_POSIX")))
            let url = directory.appending(path: name + "-" + UUID().uuidString + ".partial.caf")
            try cafHeader(format: format).write(to: url)
            let file = try FileHandle(forWritingTo: url)
            try file.seekToEnd()
            sources[source] = Source(file: file, url: url)
        }
        try sources[source]?.file.write(contentsOf: interleavedFloatData(pcm))
        sources[source]?.frames += count
        if Double(sources[source]?.frames ?? 0) / format.sampleRate >= chunkDuration {
            try close(source)
        }
    }

    func close() throws {
        for source in Array(sources.keys) { try close(source) }
    }

    private func close(_ source: String) throws {
        guard let current = sources.removeValue(forKey: source) else { return }
        defer { try? current.file.close() }
        let finished = current.url.deletingPathExtension().deletingPathExtension().appendingPathExtension("caf")
        try FileManager.default.moveItem(at: current.url, to: finished)
        try RecordingFileSync.synchronize(current.file)
    }

    /// CAF permits an unknown data-chunk size (-1). Unlike WAV, even the open
    /// fragment is readable without a final header rewrite after a crash.
    private func cafHeader(format: AVAudioFormat) -> Data {
        var data = Data("caff".utf8)
        appendBigEndian(UInt16(1), to: &data)
        appendBigEndian(UInt16(0), to: &data)
        data.append(Data("desc".utf8))
        appendBigEndian(UInt64(32), to: &data)
        appendBigEndian(format.sampleRate.bitPattern, to: &data)
        data.append(Data("lpcm".utf8))
        appendBigEndian(UInt32(3), to: &data) // Float32, little endian.
        appendBigEndian(UInt32(4 * format.channelCount), to: &data)
        appendBigEndian(UInt32(1), to: &data)
        appendBigEndian(format.channelCount, to: &data)
        appendBigEndian(UInt32(32), to: &data)
        data.append(Data("data".utf8))
        appendBigEndian(UInt64.max, to: &data)
        appendBigEndian(UInt32(0), to: &data) // Edit count.
        return data
    }

    private func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }

    private func interleavedFloatData(_ pcm: AVAudioPCMBuffer) throws -> Data {
        let channels = Int(pcm.format.channelCount)
        let interleaved = pcm.format.isInterleaved
        let frameCount = Int(pcm.frameLength)
        var samples = [Float](repeating: 0, count: frameCount * channels)
        for frame in 0..<frameCount {
            for channel in 0..<channels {
                let sourceChannel = interleaved ? 0 : channel
                let sourceIndex = interleaved ? frame * channels + channel : frame
                let value: Float
                switch pcm.format.commonFormat {
                case .pcmFormatFloat32:
                    guard let pointer = pcm.floatChannelData else { throw AudioPostProcessingError.cannotReadTrack }
                    value = pointer[sourceChannel][sourceIndex]
                case .pcmFormatInt16:
                    guard let pointer = pcm.int16ChannelData else { throw AudioPostProcessingError.cannotReadTrack }
                    value = Float(pointer[sourceChannel][sourceIndex]) / 32_768
                case .pcmFormatInt32:
                    guard let pointer = pcm.int32ChannelData else { throw AudioPostProcessingError.cannotReadTrack }
                    value = Float(pointer[sourceChannel][sourceIndex]) / 2_147_483_648
                default:
                    throw AudioPostProcessingError.cannotReadTrack
                }
                samples[frame * channels + channel] = value
            }
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    deinit {
        for source in sources.values { try? source.file.close() }
    }
}
