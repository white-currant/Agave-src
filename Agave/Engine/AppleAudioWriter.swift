import AudioToolbox
import Foundation

/// Запись через ExtAudioFile — всё, что умеют кодировать системные фреймворки:
/// WAV, AIFF, FLAC, AAC, ALAC.
final class AppleAudioWriter {
    /// В каком виде кодировщику отдаются кадры.
    ///
    /// Обычно годится Float32 — система сама приведёт его к разрядности файла.
    /// Исключение — FLAC: его кодировщик определяет разрядность результата по
    /// клиентскому формату, а не по заявленному в файле, и на Float32 всегда
    /// пишет 24 бита, сколько бы ни просили. Поэтому для FLAC отдаём целые
    /// числа ровно нужной разрядности.
    private enum ClientSampleFormat {
        case float32
        case int16
        case int24
    }

    private var file: ExtAudioFileRef?
    private let clientSampleFormat: ClientSampleFormat
    private let channelCount: Int
    /// Буфер под целочисленное представление, если оно требуется.
    private var integerBuffer: UnsafeMutableRawPointer?
    private var integerBufferFrames = 0

    init(
        url: URL,
        format: OutputFormat,
        sampleRate: Double,
        channels: Int,
        bitDepth: BitDepth,
        bitrate: BitrateMode
    ) throws {
        channelCount = channels
        if format == .flac {
            clientSampleFormat = bitDepth.rawValue >= 24 ? .int24 : .int16
        } else {
            clientSampleFormat = .float32
        }

        var outputFormat = try Self.outputFormat(
            format: format, sampleRate: sampleRate, channels: channels, bitDepth: bitDepth
        )

        var reference: ExtAudioFileRef?
        try ConversionError.check(
            ExtAudioFileCreateWithURL(
                url as CFURL,
                format.audioFileType,
                &outputFormat,
                nil,
                AudioFileFlags.eraseFile.rawValue,
                &reference
            ),
            "Не удалось создать файл \(format.title)"
        )
        guard let reference else {
            throw ConversionError("Не удалось создать файл \(format.title)")
        }
        file = reference

        var clientFormat = Self.clientFormat(
            clientSampleFormat, sampleRate: sampleRate, channels: channels
        )
        try ConversionError.check(
            ExtAudioFileSetProperty(
                reference,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                &clientFormat
            ),
            "Кодировщик не принял поток"
        )

        if format == .aac {
            applyBitrate(bitrate, to: reference)
        }
    }

    deinit {
        if let file {
            ExtAudioFileDispose(file)
        }
        integerBuffer?.deallocate()
    }

    func write(_ buffer: UnsafeMutablePointer<Float>, frames: Int, channels: Int) throws {
        guard let file, frames > 0 else { return }

        let bytesPerChannel: Int
        let data: UnsafeMutableRawPointer

        switch clientSampleFormat {
        case .float32:
            bytesPerChannel = 4
            data = UnsafeMutableRawPointer(buffer)
        case .int16:
            bytesPerChannel = 2
            data = try convertToIntegers(buffer, frames: frames, bytesPerChannel: 2)
        case .int24:
            bytesPerChannel = 4
            data = try convertToIntegers(buffer, frames: frames, bytesPerChannel: 4)
        }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(frames * channels * bytesPerChannel),
                mData: data
            )
        )
        try ConversionError.check(
            ExtAudioFileWrite(file, UInt32(frames), &bufferList),
            "Ошибка записи"
        )
    }

    /// Переводит Float32 в целые числа нужной разрядности с ограничением по шкале.
    private func convertToIntegers(
        _ buffer: UnsafeMutablePointer<Float>, frames: Int, bytesPerChannel: Int
    ) throws -> UnsafeMutableRawPointer {
        let samples = frames * channelCount
        if integerBuffer == nil || integerBufferFrames < frames {
            integerBuffer?.deallocate()
            integerBuffer = UnsafeMutableRawPointer.allocate(
                byteCount: samples * bytesPerChannel, alignment: 4
            )
            integerBufferFrames = frames
        }
        guard let target = integerBuffer else {
            throw ConversionError("Не удалось выделить память под преобразование")
        }

        // Масштаб обратного преобразования — 32768, а не 32767: система переводит
        // целые в дробные делением на 32768, и только такой множитель возвращает
        // исходные значения без потери единицы младшего разряда.
        if bytesPerChannel == 2 {
            let out = target.assumingMemoryBound(to: Int16.self)
            for index in 0..<samples {
                let value = (buffer[index] * 32768).rounded()
                out[index] = Int16(max(-32768, min(32767, value)))
            }
        } else {
            // 24 значащих бита в 32-битной ячейке, выровненные вправо.
            let out = target.assumingMemoryBound(to: Int32.self)
            for index in 0..<samples {
                let value = (buffer[index] * 8_388_608).rounded()
                out[index] = Int32(max(-8_388_608, min(8_388_607, value)))
            }
        }
        return target
    }

    private static func clientFormat(
        _ kind: ClientSampleFormat, sampleRate: Double, channels: Int
    ) -> AudioStreamBasicDescription {
        var flags: AudioFormatFlags
        var bits: UInt32
        var bytesPerChannel: UInt32

        switch kind {
        case .float32:
            flags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            bits = 32
            bytesPerChannel = 4
        case .int16:
            flags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
            bits = 16
            bytesPerChannel = 2
        case .int24:
            // Без флага упаковки: 24 бита лежат в 32-битной ячейке.
            flags = kAudioFormatFlagIsSignedInteger
            bits = 24
            bytesPerChannel = 4
        }

        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: flags,
            mBytesPerPacket: bytesPerChannel * UInt32(channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerChannel * UInt32(channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: bits,
            mReserved: 0
        )
    }

    func finish() {
        if let file {
            ExtAudioFileDispose(file)
            self.file = nil
        }
    }

    // MARK: - Формат назначения

    private static func outputFormat(
        format: OutputFormat, sampleRate: Double, channels: Int, bitDepth: BitDepth
    ) throws -> AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        asbd.mSampleRate = sampleRate
        asbd.mChannelsPerFrame = UInt32(channels)

        switch format {
        case .wav, .aiff:
            let bits = UInt32(bitDepth.rawValue)
            var flags = kAudioFormatFlagIsPacked
            flags |= bitDepth.isFloat ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger
            if format == .aiff {
                flags |= kAudioFormatFlagIsBigEndian
            }
            asbd.mFormatID = kAudioFormatLinearPCM
            asbd.mFormatFlags = flags
            asbd.mBitsPerChannel = bits
            asbd.mFramesPerPacket = 1
            asbd.mBytesPerFrame = UInt32(channels) * bits / 8
            asbd.mBytesPerPacket = asbd.mBytesPerFrame
            return asbd

        case .flac:
            asbd.mFormatID = kAudioFormatFLAC
            asbd.mBitsPerChannel = UInt32(bitDepth.rawValue)

        case .alac:
            asbd.mFormatID = kAudioFormatAppleLossless
            asbd.mFormatFlags = bitDepth.rawValue == 24
                ? kAppleLosslessFormatFlag_24BitSourceData
                : kAppleLosslessFormatFlag_16BitSourceData

        case .aac:
            asbd.mFormatID = kAudioFormatMPEG4AAC

        case .mp3, .ogg:
            throw ConversionError("\(format.title) пишется отдельным кодировщиком")
        }

        // Остальные поля (размер пакета, число кадров в пакете) заполняет система.
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try ConversionError.check(
            AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &asbd),
            "Система не поддерживает \(format.title) с такими параметрами"
        )
        return asbd
    }

    // MARK: - Битрейт AAC

    private func applyBitrate(_ bitrate: BitrateMode, to file: ExtAudioFileRef) {
        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        let status = withUnsafeMutablePointer(to: &converter) { pointer in
            ExtAudioFileGetProperty(
                file, kExtAudioFileProperty_AudioConverter, &size, pointer
            )
        }
        guard status == noErr, let converter else { return }

        var target = UInt32(bitrate.approximateKilobits * 1000)
        if let nearest = nearestSupportedBitrate(to: target, converter: converter) {
            target = nearest
        }
        AudioConverterSetProperty(
            converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &target
        )

        // Обязательный пинок: без пустой конфигурации ExtAudioFile не подхватит
        // изменённые настройки конвертера.
        var config: CFPropertyList?
        withUnsafePointer(to: &config) { pointer in
            _ = ExtAudioFileSetProperty(
                file,
                kExtAudioFileProperty_ConverterConfig,
                UInt32(MemoryLayout<CFPropertyList?>.size),
                pointer
            )
        }
    }

    /// Кодировщик AAC принимает не любой битрейт — выбираем ближайший из разрешённых.
    private func nearestSupportedBitrate(
        to target: UInt32, converter: AudioConverterRef
    ) -> UInt32? {
        var size: UInt32 = 0
        guard AudioConverterGetPropertyInfo(
            converter, kAudioConverterApplicableEncodeBitRates, &size, nil
        ) == noErr, size > 0 else { return nil }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard AudioConverterGetProperty(
            converter, kAudioConverterApplicableEncodeBitRates, &size, &ranges
        ) == noErr else { return nil }

        let wanted = Double(target)
        var best: Double?
        for range in ranges where range.mMaximum > 0 {
            let clamped = min(max(wanted, range.mMinimum), range.mMaximum)
            if best == nil || abs(clamped - wanted) < abs(best! - wanted) {
                best = clamped
            }
        }
        return best.map { UInt32($0) }
    }
}
