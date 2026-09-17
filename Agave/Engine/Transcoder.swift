import AudioToolbox
import Foundation

/// Перегоняет один файл. Синхронный и блокирующий — вызывается с фонового потока.
enum Transcoder {

    /// Сколько кадров читаем за раз. 16 384 — компромисс между числом
    /// системных вызовов и объёмом памяти на поток.
    private static let chunkFrames = 16_384

    static func convert(
        source: URL,
        destination: URL,
        settings: ConversionSettings,
        onProgress: (Double) -> Void,
        isCancelled: () -> Bool
    ) throws {
        guard let info = AudioProbe.probe(source) else {
            throw ConversionError("Не похоже на звуковой файл")
        }

        let format = settings.format
        var targetRate = settings.sampleRate.hertz ?? info.sampleRate
        if let ceiling = format.maxSampleRate {
            targetRate = min(targetRate, ceiling)
        }
        if format == .mp3 {
            targetRate = MP3Writer.legalSampleRate(for: targetRate)
        }
        let targetChannels = max(
            1, min(settings.channels.count ?? info.channels, format.maxChannels)
        )
        let bitDepth = format.resolvedBitDepth(settings.bitDepth)
        let tags = settings.copyMetadata ? AudioProbe.tags(source) : nil

        // Ogg Vorbis система читать не умеет — разворачиваем его во временный
        // несжатый файл, дальше работает общий конвейер.
        var decodedInput: URL?
        defer {
            if let decodedInput {
                try? FileManager.default.removeItem(at: decodedInput)
            }
        }
        let readerSource: URL
        if info.requiresVorbisDecoding {
            let decoded = try VorbisDecoder.decodeToTemporaryFile(source)
            decodedInput = decoded
            readerSource = decoded
        } else {
            readerSource = source
        }

        let reader = try PCMReader(
            url: readerSource,
            targetSampleRate: targetRate,
            targetChannels: targetChannels,
            channelLimit: format.maxChannels
        )

        let temporaryURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".agave-\(UUID().uuidString).tmp")

        var cleanupOnFailure = true
        defer {
            if cleanupOnFailure {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let buffer = UnsafeMutablePointer<Float>.allocate(
            capacity: chunkFrames * reader.channels
        )
        defer { buffer.deallocate() }

        switch format {
        case .mp3:
            let writer = try MP3Writer(
                url: temporaryURL,
                sampleRate: reader.sampleRate,
                channels: reader.channels,
                bitrate: settings.bitrate,
                tags: tags
            )
            try pump(reader: reader, buffer: buffer, onProgress: onProgress, isCancelled: isCancelled) {
                frames in
                try writer.write(buffer, frames: frames)
            }
            try writer.finish()

        case .ogg:
            let writer = try VorbisWriter(
                url: temporaryURL,
                sampleRate: reader.sampleRate,
                channels: reader.channels,
                bitrate: settings.bitrate,
                tags: tags
            )
            try pump(reader: reader, buffer: buffer, onProgress: onProgress, isCancelled: isCancelled) {
                frames in
                try writer.write(buffer, frames: frames)
            }
            try writer.finish()

        default:
            let writer = try AppleAudioWriter(
                url: temporaryURL,
                format: format,
                sampleRate: reader.sampleRate,
                channels: reader.channels,
                bitDepth: bitDepth,
                bitrate: settings.bitrate
            )
            try pump(reader: reader, buffer: buffer, onProgress: onProgress, isCancelled: isCancelled) {
                frames in
                try writer.write(buffer, frames: frames, channels: reader.channels)
            }
            writer.finish()
        }

        try place(temporaryURL, at: destination)
        cleanupOnFailure = false

        // Теги пишем уже по конечному пути: контейнер определяется по расширению,
        // а у временного файла оно служебное. MP3 и OGG получают теги от своих
        // кодировщиков прямо при записи.
        if let tags, format == .aac || format == .alac {
            MP4TagWriter.apply(tags, to: destination)
        }
        onProgress(1)
    }

    /// Общий цикл «прочитал — отдал кодировщику».
    private static func pump(
        reader: PCMReader,
        buffer: UnsafeMutablePointer<Float>,
        onProgress: (Double) -> Void,
        isCancelled: () -> Bool,
        write: (Int) throws -> Void
    ) throws {
        var framesDone: Int64 = 0
        let total = reader.expectedFrameCount

        while true {
            if isCancelled() {
                throw CancellationError()
            }
            let frames = try reader.read(into: buffer, capacityFrames: chunkFrames)
            if frames == 0 { break }
            try write(frames)

            framesDone += Int64(frames)
            if total > 0 {
                onProgress(min(0.999, Double(framesDone) / Double(total)))
            }
        }
    }

    private static func place(_ temporary: URL, at destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: destination)
        }
    }
}

