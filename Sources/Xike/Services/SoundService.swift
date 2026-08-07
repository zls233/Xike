import AppKit
import AVFoundation
import Foundation

struct SoundOption: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case builtIn
        case system
    }

    let id: String
    let displayName: String
    let source: Source
    let fileURL: URL?
}

enum SoundServiceError: LocalizedError {
    case audioEngineUnavailable(String)
    case soundUnavailable(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .audioEngineUnavailable(let details):
            "无法启动音频引擎：\(details)"
        case .soundUnavailable(let name):
            "提示音“\(name)”当前不可用。"
        case .playbackFailed(let name):
            "无法播放提示音“\(name)”。"
        }
    }
}

/// Owns only audio playback. Session state and sound preferences remain in the SwiftUI layer.
@MainActor
final class SoundService {
    enum BuiltInTone: String, CaseIterable, Sendable {
        case softBell
        case warmDrops
        case clearBreeze

        var id: String { "builtin:\(rawValue)" }

        var displayName: String {
            switch self {
            case .softBell: "柔铃"
            case .warmDrops: "暖滴"
            case .clearBreeze: "清风"
            }
        }

        fileprivate var duration: TimeInterval {
            switch self {
            case .softBell: 0.82
            case .warmDrops: 0.92
            case .clearBreeze: 0.72
            }
        }
    }

    static let defaultSoundID = BuiltInTone.softBell.id

    private let audioEngine = AVAudioEngine()
    private let audioPlayer = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat
    private let randomIndex: (Int) -> Int
    private var cachedBuffers: [BuiltInTone: AVAudioPCMBuffer] = [:]
    private var activeSystemSound: NSSound?
    private var lastPlayedSoundID: String?
    private var audioSetupError: String?

    private(set) var availableSounds: [SoundOption] = []

    init(randomIndex: @escaping (Int) -> Int = { upperBound in
        Int.random(in: 0 ..< upperBound)
    }) {
        self.randomIndex = randomIndex
        self.audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1
        )!

        audioEngine.attach(audioPlayer)
        if #available(macOS 27.0, *) {
            do {
                try audioEngine.connectNode(
                    audioPlayer,
                    to: audioEngine.mainMixerNode,
                    format: audioFormat
                )
            } catch {
                audioSetupError = error.localizedDescription
            }
        } else {
            connectAudioEngineBeforeMacOS27()
        }
        audioEngine.prepare()
        availableSounds = Self.builtInOptions + Self.discoverSystemSounds()
    }

    /// Re-scans system and user Library sound folders. Call after a sound is installed or removed.
    @discardableResult
    func refreshAvailableSounds() -> [SoundOption] {
        availableSounds = Self.builtInOptions + Self.discoverSystemSounds()
        return availableSounds
    }

    /// Plays the configured alert, returning the actual sound ID (including fallback) that started.
    @discardableResult
    func playAlert(
        soundIDs: [String],
        mode: SoundSelectionMode,
        volume: Double
    ) throws -> String {
        let selected = selectSound(from: soundIDs, mode: mode)

        do {
            try play(selected, volume: volume)
            lastPlayedSoundID = selected.id
            return selected.id
        } catch {
            XikeLog.audio.error(
                "Configured sound failed; using fallback. sound=\(selected.id, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )

            guard selected.id != Self.defaultSoundID,
                  let fallback = availableSounds.first(where: { $0.id == Self.defaultSoundID })
            else {
                throw error
            }

            try play(fallback, volume: volume)
            lastPlayedSoundID = fallback.id
            return fallback.id
        }
    }

    @discardableResult
    func playAlert(configuration: FocusConfiguration) throws -> String {
        try playAlert(
            soundIDs: configuration.selectedSoundIDs,
            mode: configuration.soundMode,
            volume: configuration.volume
        )
    }

    /// Previews one sound. Invalid or removed system sounds fall back to the default built-in tone.
    @discardableResult
    func preview(soundID: String, volume: Double) throws -> String {
        try playAlert(soundIDs: [soundID], mode: .fixed, volume: volume)
    }

    func stop() {
        activeSystemSound?.stop()
        activeSystemSound = nil
        audioPlayer.stop()
    }

    private func selectSound(from requestedIDs: [String], mode: SoundSelectionMode) -> SoundOption {
        let requested = Set(requestedIDs)
        var candidates = availableSounds.filter { requested.contains($0.id) }

        if candidates.isEmpty,
           let fallback = availableSounds.first(where: { $0.id == Self.defaultSoundID }) {
            return fallback
        }

        guard mode == .random, candidates.count > 1 else {
            return candidates[0]
        }

        if let lastPlayedSoundID {
            candidates.removeAll { $0.id == lastPlayedSoundID }
        }

        let safeIndex = min(max(randomIndex(candidates.count), 0), candidates.count - 1)
        return candidates[safeIndex]
    }

    private func play(_ option: SoundOption, volume: Double) throws {
        stop()
        let clampedVolume = Float(min(max(volume, 0), 1))

        switch option.source {
        case .builtIn:
            guard let tone = BuiltInTone.allCases.first(where: { $0.id == option.id }) else {
                throw SoundServiceError.soundUnavailable(option.displayName)
            }
            try play(tone: tone, volume: clampedVolume)

        case .system:
            guard let url = option.fileURL,
                  let sound = NSSound(contentsOf: url, byReference: true)
            else {
                throw SoundServiceError.soundUnavailable(option.displayName)
            }
            sound.volume = clampedVolume
            activeSystemSound = sound
            guard sound.play() else {
                activeSystemSound = nil
                throw SoundServiceError.playbackFailed(option.displayName)
            }
        }
    }

    private func play(tone: BuiltInTone, volume: Float) throws {
        if let audioSetupError {
            throw SoundServiceError.audioEngineUnavailable(audioSetupError)
        }

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                throw SoundServiceError.audioEngineUnavailable(error.localizedDescription)
            }
        }

        let buffer: AVAudioPCMBuffer
        if let cached = cachedBuffers[tone] {
            buffer = cached
        } else {
            let generated = Self.makeBuffer(for: tone, format: audioFormat)
            cachedBuffers[tone] = generated
            buffer = generated
        }

        audioPlayer.volume = volume
        audioPlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if #available(macOS 27.0, *) {
            do {
                try audioPlayer.playAudio(at: nil)
            } catch {
                throw SoundServiceError.playbackFailed(tone.displayName)
            }
        } else {
            playAudioBeforeMacOS27()
        }
    }

    @available(macOS, introduced: 10.10, obsoleted: 27.0)
    private func connectAudioEngineBeforeMacOS27() {
        audioEngine.connect(audioPlayer, to: audioEngine.mainMixerNode, format: audioFormat)
    }

    @available(macOS, introduced: 10.10, obsoleted: 27.0)
    private func playAudioBeforeMacOS27() {
        audioPlayer.play()
    }

    private static var builtInOptions: [SoundOption] {
        BuiltInTone.allCases.map { tone in
            SoundOption(
                id: tone.id,
                displayName: tone.displayName,
                source: .builtIn,
                fileURL: nil
            )
        }
    }

    private static func discoverSystemSounds() -> [SoundOption] {
        let fileManager = FileManager.default
        var directories = [
            URL(filePath: "/System/Library/Sounds", directoryHint: .isDirectory),
            URL(filePath: "/Library/Sounds", directoryHint: .isDirectory),
        ]

        if let userLibrary = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            directories.append(userLibrary.appending(path: "Sounds", directoryHint: .isDirectory))
        }

        let supportedExtensions = Set(["aif", "aiff", "caf", "m4a", "mp3", "wav"])
        var optionsByName: [String: SoundOption] = [:]

        for directory in directories {
            guard let URLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in URLs where supportedExtensions.contains(url.pathExtension.lowercased()) {
                let name = url.deletingPathExtension().lastPathComponent
                guard !name.isEmpty,
                      NSSound(contentsOf: url, byReference: true) != nil
                else { continue }

                // Prefer the first occurrence, which makes the system folder authoritative.
                optionsByName[name] = optionsByName[name] ?? SoundOption(
                    id: "system:\(url.path(percentEncoded: false))",
                    displayName: name,
                    source: .system,
                    fileURL: url
                )
            }
        }

        return optionsByName.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func makeBuffer(for tone: BuiltInTone, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(tone.duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        guard let samples = buffer.floatChannelData?[0] else { return buffer }

        for frame in 0 ..< Int(frameCount) {
            let time = Double(frame) / sampleRate
            let position = time / tone.duration
            let attack = min(position / 0.045, 1)
            let release = pow(max(1 - position, 0), 2.4)
            let envelope = attack * release

            let sample: Double
            switch tone {
            case .softBell:
                let fundamental = sin(2 * .pi * 660 * time)
                let shimmer = 0.34 * sin(2 * .pi * 990 * time + 0.35)
                let warmth = 0.18 * sin(2 * .pi * 440 * time)
                sample = (fundamental + shimmer + warmth) * envelope * 0.34

            case .warmDrops:
                let split = tone.duration * 0.42
                let firstEnvelope = exp(-5.3 * time)
                let secondTime = max(time - split, 0)
                let secondEnvelope = time >= split ? exp(-6.2 * secondTime) : 0
                let first = sin(2 * .pi * 523.25 * time) * firstEnvelope
                let second = sin(2 * .pi * 659.25 * secondTime) * secondEnvelope
                sample = (first + 0.82 * second) * attack * 0.28

            case .clearBreeze:
                let glide = 520 + (110 * position)
                let primary = sin(2 * .pi * glide * time)
                let airy = 0.22 * sin(2 * .pi * (glide * 2.01) * time)
                sample = (primary + airy) * envelope * 0.31
            }

            samples[frame] = Float(max(min(sample, 0.9), -0.9))
        }

        return buffer
    }
}
