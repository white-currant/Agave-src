import AudioToolbox
import Foundation

/// Ошибка любого этапа конвертации с человеческим описанием.
struct ConversionError: LocalizedError {
    let message: String
    let code: OSStatus?

    init(_ message: String, code: OSStatus? = nil) {
        self.message = message
        self.code = code
    }

    var errorDescription: String? {
        guard let code, code != noErr else { return message }
        return "\(message) (код \(code))"
    }

    /// Бросает ошибку, если статус CoreAudio не noErr.
    static func check(_ status: OSStatus, _ message: @autoclosure () -> String) throws {
        guard status != noErr else { return }
        throw ConversionError(message(), code: status)
    }
}

/// Читает любой поддерживаемый системой файл и отдаёт чередующийся Float32,
/// попутно приводя частоту дискретизации и число каналов к целевым.
final class PCMReader {
    /// Собственная задержка декодера MPEG Layer III: 528 сэмплов блока синтеза плюс один.
    /// Это не звук, а артефакт декодирования, и его полагается отбрасывать.
    private static let mp3DecoderDelay = 529

    private var file: ExtAudioFileRef?
    /// Сколько кадров нужно проглотить и выбросить перед первой выдачей.
    private var framesToSkip = 0

    let sourceSampleRate: Double
    let sourceChannels: Int
    /// Частота, в которой отдаются кадры.
    let sampleRate: Double
    /// Число каналов, в котором отдаются кадры.
    let channels: Int
    /// Ожидаемое число кадров на выходе — для прогресса.
    let expectedFrameCount: Int64

    init(url: URL, targetSampleRate: Double?, targetChannels: Int?, channelLimit: Int) throws {
        var reference: ExtAudioFileRef?
        try ConversionError.check(
            ExtAudioFileOpenURL(url as CFURL, &reference),
            "Не удалось открыть файл"
        )
        guard let reference else {
            throw ConversionError("Не удалось открыть файл")
        }
        file = reference

        var sourceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try ConversionError.check(
            ExtAudioFileGetProperty(
                reference, kExtAudioFileProperty_FileDataFormat, &formatSize, &sourceFormat
            ),
            "Не удалось прочитать формат источника"
        )

        sourceSampleRate = sourceFormat.mSampleRate
        sourceChannels = Int(sourceFormat.mChannelsPerFrame)
        guard sourceSampleRate > 0, sourceChannels > 0 else {
            throw ConversionError("В файле нет звуковой дорожки")
        }

        sampleRate = targetSampleRate ?? sourceSampleRate
        channels = min(targetChannels ?? sourceChannels, channelLimit)

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try ConversionError.check(
            ExtAudioFileSetProperty(
                reference,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                &clientFormat
            ),
            "Формат источника не поддерживается"
        )

        var sourceFrames: Int64 = 0
        var framesSize = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(
            reference, kExtAudioFileProperty_FileLengthFrames, &framesSize, &sourceFrames
        )

        let total = Int64(Double(sourceFrames) * sampleRate / sourceSampleRate)
        expectedFrameCount = max(0, total - Int64(framesToSkip))
    }

    deinit {
        if let file {
            ExtAudioFileDispose(file)
        }
    }

    /// Читает до `capacityFrames` кадров. Ноль означает конец файла.
    func read(into buffer: UnsafeMutablePointer<Float>, capacityFrames: Int) throws -> Int {
        // Начальные кадры задержки декодера вычитываем в тот же буфер и выбрасываем.
        while framesToSkip > 0 {
            let chunk = min(framesToSkip, capacityFrames)
            let consumed = try rawRead(into: buffer, capacityFrames: chunk)
            if consumed == 0 {
                framesToSkip = 0
                return 0
            }
            framesToSkip -= consumed
        }
        return try rawRead(into: buffer, capacityFrames: capacityFrames)
    }

    private func rawRead(into buffer: UnsafeMutablePointer<Float>, capacityFrames: Int) throws -> Int {
        guard let file else { return 0 }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(capacityFrames * channels * 4),
                mData: UnsafeMutableRawPointer(buffer)
            )
        )
        var frames = UInt32(capacityFrames)
        try ConversionError.check(
            ExtAudioFileRead(file, &frames, &bufferList),
            "Ошибка чтения звука"
        )
        return Int(frames)
    }
}
