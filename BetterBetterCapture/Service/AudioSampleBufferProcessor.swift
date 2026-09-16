import AVFoundation
import Foundation

// MARK: - Audio Sample Processing

/// Reads and transforms PCM samples from `CMSampleBuffer` without assuming that
/// interleaved and non-interleaved audio share the same memory layout.
nonisolated enum AudioSampleBufferProcessor {
    struct Statistics {
        let sumOfSquares: Double
        let sampleCount: Int
    }

    private struct BufferSegment {
        let dataPointer: UnsafeMutableRawPointer
        let byteCount: Int
    }

    private struct BufferInfo {
        let formatDescription: CMAudioFormatDescription
        let buffers: [BufferSegment]
        let totalLength: Int
        let sampleCount: Int
        let timingInfo: CMSampleTimingInfo
        let isFloat: Bool
        let isBigEndian: Bool
        let bytesPerSample: Int
        let retainedBlockBuffer: CMBlockBuffer?
    }

    static func statistics(from sampleBuffer: CMSampleBuffer) -> Statistics? {
        guard let info = parse(sampleBuffer) else { return nil }
        return computeStatistics(from: info)
    }

    static func applyingGain(to sampleBuffer: CMSampleBuffer, multiplier: Double) -> CMSampleBuffer? {
        guard let info = parse(sampleBuffer) else { return nil }
        guard info.totalLength > 0 else { return nil }

        guard let memory = CFAllocatorAllocate(kCFAllocatorDefault, info.totalLength, 0) else {
            return nil
        }

        guard copySamples(from: info, to: memory, multiplier: multiplier) else {
            CFAllocatorDeallocate(kCFAllocatorDefault, memory)
            return nil
        }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: memory,
            blockLength: info.totalLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: info.totalLength,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else {
            CFAllocatorDeallocate(kCFAllocatorDefault, memory)
            return nil
        }

        var newSampleBuffer: CMSampleBuffer?
        var timingInfo = info.timingInfo
        let sampleStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: info.formatDescription,
            sampleCount: info.sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &newSampleBuffer
        )
        guard sampleStatus == noErr, let newSampleBuffer else {
            return nil
        }

        return newSampleBuffer
    }

    private static func parse(_ sampleBuffer: CMSampleBuffer) -> BufferInfo? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        var bufferListSize = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &bufferListSize, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: nil
        )
        guard sizeStatus == noErr, bufferListSize > 0 else { return nil }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        let bufferStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: audioBufferList, bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &retainedBlockBuffer
        )
        guard bufferStatus == noErr else { return nil }

        var segments: [BufferSegment] = []
        var totalLength = 0
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            guard let dataPointer = buffer.mData, buffer.mDataByteSize > 0 else {
                continue
            }
            let byteCount = Int(buffer.mDataByteSize)
            segments.append(BufferSegment(dataPointer: dataPointer, byteCount: byteCount))
            totalLength += byteCount
        }
        guard !segments.isEmpty, totalLength > 0 else { return nil }

        let bytesPerSample = Int(asbd.pointee.mBitsPerChannel) / 8
        let isFloat = asbd.pointee.mFormatFlags & kLinearPCMFormatFlagIsFloat != 0
        let isBigEndian = asbd.pointee.mFormatFlags & kLinearPCMFormatFlagIsBigEndian != 0

        guard bytesPerSample > 0 else { return nil }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        var timingInfo = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo) == noErr else {
            return nil
        }

        return BufferInfo(
            formatDescription: formatDescription, buffers: segments, totalLength: totalLength,
            sampleCount: sampleCount, timingInfo: timingInfo,
            isFloat: isFloat, isBigEndian: isBigEndian, bytesPerSample: bytesPerSample,
            retainedBlockBuffer: retainedBlockBuffer
        )
    }

    private static func computeStatistics(from info: BufferInfo) -> Statistics? {
        var sum: Double = 0
        var sampleCount = 0

        for buffer in info.buffers {
            let samplesInBuffer = buffer.byteCount / info.bytesPerSample

            if info.isFloat && info.bytesPerSample == MemoryLayout<Float>.size {
                let samples = buffer.dataPointer.bindMemory(to: Float.self, capacity: samplesInBuffer)
                for index in 0..<samplesInBuffer {
                    let sample = Double(samples[index])
                    sum += sample * sample
                    sampleCount += 1
                }
            } else if !info.isFloat && info.bytesPerSample == MemoryLayout<Int16>.size {
                let samples = buffer.dataPointer.bindMemory(to: Int16.self, capacity: samplesInBuffer)
                for index in 0..<samplesInBuffer {
                    let rawValue = samples[index]
                    let sampleValue = info.isBigEndian ? Int16(bigEndian: rawValue) : rawValue
                    let normalized = Double(sampleValue) / Double(Int16.max)
                    sum += normalized * normalized
                    sampleCount += 1
                }
            } else {
                return nil
            }
        }

        guard sampleCount > 0 else { return nil }
        return Statistics(sumOfSquares: sum, sampleCount: sampleCount)
    }

    private static func copySamples(
        from info: BufferInfo,
        to memory: UnsafeMutableRawPointer,
        multiplier: Double
    ) -> Bool {
        var destinationOffset = 0

        for buffer in info.buffers {
            let samplesInBuffer = buffer.byteCount / info.bytesPerSample
            let destinationPointer = memory.advanced(by: destinationOffset)

            if info.isFloat && info.bytesPerSample == MemoryLayout<Float>.size {
                let source = buffer.dataPointer.bindMemory(to: Float.self, capacity: samplesInBuffer)
                let destination = destinationPointer.bindMemory(to: Float.self, capacity: samplesInBuffer)
                for index in 0..<samplesInBuffer {
                    destination[index] = Float(limitedSample(Double(source[index]) * multiplier))
                }
            } else if !info.isFloat && info.bytesPerSample == MemoryLayout<Int16>.size {
                let source = buffer.dataPointer.bindMemory(to: Int16.self, capacity: samplesInBuffer)
                let destination = destinationPointer.bindMemory(to: Int16.self, capacity: samplesInBuffer)
                for index in 0..<samplesInBuffer {
                    let rawValue = source[index]
                    let sampleValue = info.isBigEndian ? Int16(bigEndian: rawValue) : rawValue
                    let normalized = Double(sampleValue) / Double(Int16.max)
                    let scaled = limitedSample(normalized * multiplier)
                    let clamped = Int16(max(Double(Int16.min), min(Double(Int16.max), scaled * Double(Int16.max))))
                    destination[index] = info.isBigEndian ? clamped.bigEndian : clamped
                }
            } else {
                return false
            }

            destinationOffset += buffer.byteCount
        }

        return true
    }

    private static func limitedSample(_ sample: Double) -> Double {
        let threshold = 0.95

        if sample > threshold {
            return threshold + (1 - threshold) * tanh((sample - threshold) / (1 - threshold))
        }
        if sample < -threshold {
            return -threshold + (1 - threshold) * tanh((sample + threshold) / (1 - threshold))
        }
        return sample
    }
}
