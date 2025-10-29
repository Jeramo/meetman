//
//  WavFileWriter.swift
//  MeetingCopilot
//
//  WAV file format writer for raw PCM audio
//

import Foundation
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "audio")

/// Writes PCM audio buffers to WAV file
public final class WavFileWriter {

    private let fileURL: URL
    private var fileHandle: FileHandle?
    private var samplesWritten: Int64 = 0
    private let sampleRate: Double
    private let channels: Int
    private let bitDepth: Int

    /// Initialize writer with file URL and audio format
    public init(
        fileURL: URL,
        sampleRate: Double = 16000,
        channels: Int = 1,
        bitDepth: Int = 16
    ) throws {
        self.fileURL = fileURL
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth

        try createFile()
        try writeWAVHeader()
    }

    private func createFile() throws {
        // Create parent directory if needed
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Create empty file
        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            throw AudioError.fileWriteFailed
        }

        fileHandle = try FileHandle(forWritingTo: fileURL)
        logger.info("Created WAV file at \(self.fileURL.path)")
    }

    private func writeWAVHeader() throws {
        guard let handle = fileHandle else {
            throw AudioError.fileWriteFailed
        }

        // Write placeholder header (will update with correct size at finalize)
        var header = WavHeader(
            sampleRate: UInt32(sampleRate),
            channels: UInt16(channels),
            bitDepth: UInt16(bitDepth),
            dataSize: 0 // Updated at finalize
        )

        let headerData = Data(bytes: &header, count: MemoryLayout<WavHeader>.size)
        try handle.write(contentsOf: headerData)
    }

    /// Write PCM samples from AVAudioPCMBuffer
    public func write(buffer: AVAudioPCMBuffer) throws {
        guard let handle = fileHandle else {
            throw AudioError.fileWriteFailed
        }

        guard let channelData = buffer.int16ChannelData else {
            throw AudioError.invalidAudioFormat
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Interleave samples if multi-channel
        var samples: [Int16] = []
        samples.reserveCapacity(frameLength * channelCount)

        for frame in 0..<frameLength {
            for ch in 0..<channelCount {
                samples.append(channelData[ch][frame])
            }
        }

        let data = samples.withUnsafeBytes { Data($0) }
        try handle.write(contentsOf: data)

        samplesWritten += Int64(samples.count)
    }

    /// Finalize file by updating header with correct sizes
    public func finalize() throws {
        guard let handle = fileHandle else { return }

        // Update header with actual data size
        let bytesPerSample = bitDepth / 8
        let dataSize = UInt32(samplesWritten * Int64(bytesPerSample))

        var header = WavHeader(
            sampleRate: UInt32(sampleRate),
            channels: UInt16(channels),
            bitDepth: UInt16(bitDepth),
            dataSize: dataSize
        )

        try handle.seek(toOffset: 0)
        let headerData = Data(bytes: &header, count: MemoryLayout<WavHeader>.size)
        try handle.write(contentsOf: headerData)

        try handle.close()
        fileHandle = nil

        logger.info("Finalized WAV file: \(self.samplesWritten) samples, \(dataSize) bytes")
    }

    deinit {
        try? fileHandle?.close()
    }
}

// MARK: - WAV Header Structure

private struct WavHeader {
    // RIFF chunk
    let riffID: (UInt8, UInt8, UInt8, UInt8) = (0x52, 0x49, 0x46, 0x46) // "RIFF"
    let riffSize: UInt32
    let waveID: (UInt8, UInt8, UInt8, UInt8) = (0x57, 0x41, 0x56, 0x45) // "WAVE"

    // fmt chunk
    let fmtID: (UInt8, UInt8, UInt8, UInt8) = (0x66, 0x6D, 0x74, 0x20) // "fmt "
    let fmtSize: UInt32 = 16 // PCM
    let audioFormat: UInt16 = 1 // PCM
    let numChannels: UInt16
    let sampleRate: UInt32
    let byteRate: UInt32
    let blockAlign: UInt16
    let bitsPerSample: UInt16

    // data chunk
    let dataID: (UInt8, UInt8, UInt8, UInt8) = (0x64, 0x61, 0x74, 0x61) // "data"
    let dataSize: UInt32

    init(sampleRate: UInt32, channels: UInt16, bitDepth: UInt16, dataSize: UInt32) {
        self.numChannels = channels
        self.sampleRate = sampleRate
        self.bitsPerSample = bitDepth
        self.blockAlign = channels * (bitDepth / 8)
        self.byteRate = sampleRate * UInt32(blockAlign)
        self.dataSize = dataSize
        self.riffSize = 36 + dataSize
    }
}
