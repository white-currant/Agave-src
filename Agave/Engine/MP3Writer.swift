import Foundation
import LameKit

/// Запись MP3 через LAME. Системные фреймворки MP3 не кодируют — только читают,
/// поэтому это единственный формат со сторонним кодировщиком.
final class MP3Writer {
    /// Частоты, которые допускает стандарт MPEG.
    static let legalSampleRates: [Double] = [
        8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
    ]

    /// Подбирает ближайшую допустимую частоту к запрошенной.
    static func legalSampleRate(for requested: Double) -> Double {
        if legalSampleRates.contains(requested) { return requested }
        if requested > 48000 {
            // 88,2 и 176,4 кГц кратны 44,1 — для них ресемплинг чище.
            return requested.truncatingRemainder(dividingBy: 44100) == 0 ? 44100 : 48000
        }
        return legalSampleRates.first { $0 >= requested } ?? 48000
    }

    private let lame: lame_t
    private let handle: FileHandle
    private let channels: Int
    private var mp3Buffer: [UInt8]
    private var isClosed = false

    init(
        url: URL,
        sampleRate: Double,
        channels: Int,
        bitrate: BitrateMode,
        tags: AudioProbe.Tags?
    ) throws {
        guard let lame = lame_init() else {
            throw ConversionError("Не удалось запустить кодировщик MP3")
        }
        self.lame = lame
        self.channels = channels

        lame_set_in_samplerate(lame, Int32(sampleRate))
        lame_set_out_samplerate(lame, Int32(sampleRate))
        lame_set_num_channels(lame, Int32(channels))
        lame_set_mode(lame, channels == 1 ? MONO : JOINT_STEREO)
        // 2 — практически лучшее качество при вменяемой скорости.
        lame_set_quality(lame, 2)
        lame_set_bWriteVbrTag(lame, 1)

        switch bitrate {
        case .constant(let kbps):
            lame_set_VBR(lame, vbr_off)
            lame_set_brate(lame, Int32(kbps))
        case .variable(let quality):
            lame_set_VBR(lame, vbr_mtrh)
            lame_set_VBR_quality(lame, Float(quality))
        }

        if let tags {
            Self.apply(tags, to: lame)
        }

        guard lame_init_params(lame) >= 0 else {
            lame_close(lame)
            throw ConversionError("Кодировщик MP3 не принял параметры")
        }

        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            lame_close(lame)
            throw ConversionError("Не удалось создать файл в папке экспорта")
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            lame_close(lame)
            throw ConversionError("Не удалось открыть файл для записи")
        }

        mp3Buffer = []
    }

    deinit {
        if !isClosed {
            try? handle.close()
            lame_close(lame)
        }
    }

    func write(_ buffer: UnsafeMutablePointer<Float>, frames: Int) throws {
        guard frames > 0 else { return }

        let needed = Int(Double(frames) * 1.25) + 7200
        if mp3Buffer.count < needed {
            mp3Buffer = [UInt8](repeating: 0, count: needed)
        }

        let written = mp3Buffer.withUnsafeMutableBufferPointer { output -> Int32 in
            if channels == 1 {
                // Функция для чередующихся данных внутри LAME жёстко считает шаг равным
                // двум сэмплам, поэтому моно отдаём поканальной версией: один и тот же
                // буфер на оба входа — при одном канале правый LAME игнорирует.
                return lame_encode_buffer_ieee_float(
                    lame, buffer, buffer, Int32(frames), output.baseAddress, Int32(output.count)
                )
            }
            return lame_encode_buffer_interleaved_ieee_float(
                lame, buffer, Int32(frames), output.baseAddress, Int32(output.count)
            )
        }
        guard written >= 0 else {
            throw ConversionError("Кодировщик MP3 вернул ошибку", code: OSStatus(written))
        }
        if written > 0 {
            try handle.write(contentsOf: Data(mp3Buffer[0..<Int(written)]))
        }
    }

    /// Дописывает хвост и служебный кадр Xing/LAME с точной длительностью.
    func finish() throws {
        guard !isClosed else { return }
        isClosed = true

        var tail = [UInt8](repeating: 0, count: 8192)
        let written = tail.withUnsafeMutableBufferPointer { output in
            lame_encode_flush(lame, output.baseAddress, Int32(output.count))
        }
        if written > 0 {
            try handle.write(contentsOf: Data(tail[0..<Int(written)]))
        }

        writeLameTag()

        try handle.close()
        lame_close(lame)
    }

    private func writeLameTag() {
        let size = lame_get_lametag_frame(lame, nil, 0)
        guard size > 0 else { return }

        var frame = [UInt8](repeating: 0, count: size)
        let written = frame.withUnsafeMutableBufferPointer { output in
            lame_get_lametag_frame(lame, output.baseAddress, output.count)
        }
        guard written > 0 else { return }

        // Кадр кладётся туда, где он был зарезервирован — сразу за тегом ID3v2.
        let offset = lame_get_id3v2_tag(lame, nil, 0)
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: Data(frame[0..<written]))
            try handle.seekToEnd()
        } catch {
            // Без Xing-кадра файл остаётся валидным, просто длительность считается приблизительно.
        }
    }

    private static func apply(_ tags: AudioProbe.Tags, to lame: lame_t) {
        id3tag_init(lame)
        id3tag_add_v2(lame)

        let values = [tags.title, tags.artist, tags.album, tags.year, tags.track,
                      tags.genre, tags.comment].compactMap { $0 }
        let needsUnicode = values.contains { !$0.allSatisfy(\.isASCII) }

        guard needsUnicode else {
            if let title = tags.title { id3tag_set_title(lame, title) }
            if let artist = tags.artist { id3tag_set_artist(lame, artist) }
            if let album = tags.album { id3tag_set_album(lame, album) }
            if let year = tags.year { id3tag_set_year(lame, year) }
            if let track = tags.track { id3tag_set_track(lame, track) }
            if let genre = tags.genre { id3tag_set_genre(lame, genre) }
            if let comment = tags.comment { id3tag_set_comment(lame, comment) }
            return
        }

        // ID3v1 умеет только latin-1: кириллица там превратится в мусор,
        // поэтому при не-ASCII пишем строго ID3v2 в UTF-16.
        id3tag_v2_only(lame)
        setUnicode(lame, "TIT2", tags.title)
        setUnicode(lame, "TPE1", tags.artist)
        setUnicode(lame, "TALB", tags.album)
        setUnicode(lame, "TYER", tags.year)
        setUnicode(lame, "TRCK", tags.track)
        setUnicode(lame, "TCON", tags.genre)
        if let comment = tags.comment {
            var text = utf16Buffer(comment)
            _ = id3tag_set_comment_utf16(lame, nil, nil, &text)
        }
    }

    private static func setUnicode(_ lame: lame_t, _ frameID: String, _ value: String?) {
        guard let value else { return }
        var text = utf16Buffer(value)
        _ = id3tag_set_textinfo_utf16(lame, frameID, &text)
    }

    /// LAME ждёт UTF-16 с меткой порядка байтов и завершающим нулём.
    private static func utf16Buffer(_ text: String) -> [UInt16] {
        [0xFEFF] + Array(text.utf16) + [0]
    }
}
