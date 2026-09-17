import AudioToolbox
import Foundation
import VorbisKit

/// Чтение Ogg Vorbis. Система этот формат не открывает, поэтому файл сначала
/// разворачивается во временный CAF с несжатым звуком, а дальше работает
/// обычный конвейер — с ресемплингом и сведением каналов средствами CoreAudio.
enum VorbisDecoder {

    static func isVorbisFile(_ url: URL) -> Bool {
        ["ogg", "oga", "ogx"].contains(url.pathExtension.lowercased())
    }

    static func probe(_ url: URL) -> AudioProbe.Info? {
        withFile(url) { file in
            guard let info = ov_info(file, -1) else { return nil }
            let frames = ov_pcm_total(file, -1)
            let rate = Double(info.pointee.rate)
            return AudioProbe.Info(
                formatLabel: "Vorbis",
                sampleRate: rate,
                channels: Int(info.pointee.channels),
                duration: frames > 0 && rate > 0 ? Double(frames) / rate : nil,
                requiresVorbisDecoding: true
            )
        }
    }

    static func tags(_ url: URL) -> AudioProbe.Tags? {
        withFile(url) { file in
            guard let comment = ov_comment(file, -1) else { return nil }
            var values: [String: String] = [:]
            for index in 0..<Int(comment.pointee.comments) {
                guard let entry = comment.pointee.user_comments[index],
                      let text = String(validatingUTF8: entry),
                      let separator = text.firstIndex(of: "=")
                else { continue }
                let key = text[text.startIndex..<separator].uppercased()
                let value = String(text[text.index(after: separator)...])
                if !value.isEmpty, values[key] == nil {
                    values[key] = value
                }
            }
            guard !values.isEmpty else { return nil }
            let tags = AudioProbe.Tags(
                title: values["TITLE"],
                artist: values["ARTIST"],
                album: values["ALBUM"],
                year: values["DATE"] ?? values["YEAR"],
                track: values["TRACKNUMBER"],
                genre: values["GENRE"],
                comment: values["COMMENT"] ?? values["DESCRIPTION"]
            )
            return tags.isEmpty ? nil : tags
        }
    }

    /// Разворачивает файл во временный CAF. Вызывающий обязан его удалить.
    static func decodeToTemporaryFile(_ url: URL) throws -> URL {
        let file = UnsafeMutablePointer<OggVorbis_File>.allocate(capacity: 1)
        defer { file.deallocate() }

        guard ov_fopen(url.path, file) == 0 else {
            throw ConversionError("Не удалось прочитать Ogg Vorbis")
        }
        defer { ov_clear(file) }

        guard let info = ov_info(file, -1) else {
            throw ConversionError("В файле Ogg нет потока Vorbis")
        }
        let channels = Int(info.pointee.channels)
        let sampleRate = Double(info.pointee.rate)
        guard channels > 0, sampleRate > 0 else {
            throw ConversionError("Неверные параметры потока Vorbis")
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("agave-ogg-\(UUID().uuidString).caf")

        var format = AudioStreamBasicDescription(
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

        var writer: ExtAudioFileRef?
        try ConversionError.check(
            ExtAudioFileCreateWithURL(
                destination as CFURL, kAudioFileCAFType, &format, nil,
                AudioFileFlags.eraseFile.rawValue, &writer
            ),
            "Не удалось создать временный файл"
        )
        guard let writer else {
            throw ConversionError("Не удалось создать временный файл")
        }
        defer { ExtAudioFileDispose(writer) }

        try ConversionError.check(
            ExtAudioFileSetProperty(
                writer, kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format
            ),
            "Не удалось настроить временный файл"
        )

        let capacity = 8192
        var interleaved = [Float](repeating: 0, count: capacity * channels)
        var section: Int32 = 0

        while true {
            var planes: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>?
            let frames = ov_read_float(file, &planes, Int32(capacity), &section)
            if frames == 0 { break }
            guard frames > 0, let planes else {
                throw ConversionError("Поток Vorbis повреждён")
            }

            let frameCount = Int(frames)
            for channel in 0..<channels {
                guard let plane = planes[channel] else { continue }
                var index = channel
                for frame in 0..<frameCount {
                    interleaved[index] = plane[frame]
                    index += channels
                }
            }

            try interleaved.withUnsafeMutableBufferPointer { buffer in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: UInt32(channels),
                        mDataByteSize: UInt32(frameCount * channels * 4),
                        mData: UnsafeMutableRawPointer(buffer.baseAddress)
                    )
                )
                try ConversionError.check(
                    ExtAudioFileWrite(writer, UInt32(frameCount), &list),
                    "Ошибка записи временного файла"
                )
            }
        }

        return destination
    }

    private static func withFile<T>(
        _ url: URL, _ body: (UnsafeMutablePointer<OggVorbis_File>) -> T?
    ) -> T? {
        let file = UnsafeMutablePointer<OggVorbis_File>.allocate(capacity: 1)
        defer { file.deallocate() }

        guard ov_fopen(url.path, file) == 0 else { return nil }
        defer { ov_clear(file) }
        return body(file)
    }
}
