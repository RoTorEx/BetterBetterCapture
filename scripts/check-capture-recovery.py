#!/usr/bin/env python3
"""Finite crash test of the production PCM journal. Starts no service or watcher."""
from pathlib import Path
import json
import os
import signal
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[1]
construction = Path.home() / "construction_side/better-better-capture"
construction.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="recovery-check-", dir=construction) as temporary:
    root = Path(temporary)
    errors = (repo / "BetterBetterCapture/Service/AudioTrackMixer.swift").read_text().split(
        "enum AudioPostProcessingError: LocalizedError {", 1)[1]
    (root / "Errors.swift").write_text(
        "import Foundation\nnonisolated enum AudioPostProcessingError: LocalizedError {" + errors)
    (root / "main.swift").write_text(r'''
import AVFoundation
import Foundation

func sample(index: Int, frequency: Double) throws -> CMSampleBuffer {
    guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                    channels: 1, interleaved: false),
          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024),
          let values = pcm.floatChannelData?[0] else { throw AudioPostProcessingError.cannotAllocateBuffer }
    pcm.frameLength = 1024
    for frame in 0..<1024 {
        values[frame] = Float(sin(Double(index * 1024 + frame) * 2 * .pi * frequency / 48_000) * 0.2)
    }
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
        presentationTimeStamp: CMTime(value: Int64(index * 1024), timescale: 48_000), decodeTimeStamp: .invalid)
    var result: CMSampleBuffer?
    let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
        sampleCount: 1024, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result)
    guard status == noErr, let result else { throw AudioPostProcessingError.cannotReadTrack }
    guard CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
        bufferList: pcm.mutableAudioBufferList) == noErr else { throw AudioPostProcessingError.cannotReadTrack }
    return result
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let journal = try AudioRecoveryJournal(directory: directory)
for index in 0..<600 {
    try journal.append(sample(index: index, frequency: 440), source: "system", origin: .zero)
    try journal.append(sample(index: index, frequency: 660), source: "microphone", origin: .zero)
    if index == 110 { try Data("ready".utf8).write(to: directory.appending(path: "ready")) }
    Thread.sleep(forTimeInterval: 0.01)
}
// Finite fallback if the controller itself dies; never a persistent process.
try journal.close()
''')
    subprocess.run([
        "xcrun", "swiftc", str(root / "main.swift"), str(root / "Errors.swift"),
        str(repo / "BetterBetterCapture/Service/AudioRecoveryJournal.swift"),
        str(repo / "BetterBetterCapture/Service/RecordingFileSync.swift"),
        "-o", str(root / "journal")], check=True)
    media = root / "audio"
    child = subprocess.Popen([str(root / "journal"), str(media)])
    try:
        deadline = time.monotonic() + 10
        while not (media / "ready").exists():
            if child.poll() is not None or time.monotonic() > deadline:
                raise RuntimeError("Journal did not checkpoint both sources")
            time.sleep(0.02)
        os.kill(child.pid, signal.SIGKILL)
        assert child.wait(timeout=5) == -signal.SIGKILL
        report = {}
        for source in ("system", "microphone"):
            chunks = list(media.glob(source + "-*.caf"))
            assert chunks, source
            frames = 0
            for chunk in chunks:
                result = subprocess.run([
                    "/opt/homebrew/bin/ffmpeg", "-v", "error", "-i", str(chunk),
                    "-f", "f32le", "-"], stdout=subprocess.PIPE, check=True)
                frames += len(result.stdout) // 4
                assert any(result.stdout), "Decoded source unexpectedly silent"
            assert frames >= 96_000, (source, frames)
            report[source] = {"fragments": len(chunks), "readable_frames": frames}
        print("SIGKILL recovery passed: " + json.dumps(report, sort_keys=True))
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=5)
