import Foundation
import VorbisKit

/// Запись Ogg Vorbis. Системные фреймворки этот формат не умеют ни читать,
/// ни писать, поэтому используется библиотека Xiph (лицензия BSD).
final class VorbisWriter {

    /// Качество VBR у Vorbis задаётся числом от -0,1 до 1,0.
    /// Наши обозначения V0…V9 наследуют шкалу MP3, где меньше — лучше.
    static func vorbisQuality(forVariable level: Int) -> Float {
        switch level {
        case 0: return 0.8   // ~256 кбит/с
        case 1: return 0.7
        case 2: return 0.6   // ~192 кбит/с
        case 3: return 0.5
        case 4: return 0.4   // ~128 кбит/с
        case 5: return 0.3
        case 6: return 0.2
        case 7: return 0.1
        case 8: return 0.0
        default: return -0.1
        }
    }

    /// Примерное соответствие качества запрошенному битрейту на 44,1 кГц стерео.
    static func vorbisQuality(forKilobits kbps: Int) -> Float {
        let table: [(kbps: Int, quality: Float)] = [
            (64, 0.0), (80, 0.1), (96, 0.2), (112, 0.3), (128, 0.4),
            (160, 0.5), (192, 0.6), (224, 0.7), (256, 0.8), (320, 0.9),
        ]
        let nearest = table.min { abs($0.kbps - kbps) < abs($1.kbps - kbps) }
        return nearest?.quality ?? 0.5
    }

    // Структуры библиотеки размещаем вручную: она хранит указатели на них
    // между вызовами, поэтому адреса должны быть стабильными.
    private let info = UnsafeMutablePointer<vorbis_info>.allocate(capacity: 1)
    private let comment = UnsafeMutablePointer<vorbis_comment>.allocate(capacity: 1)
    private let dsp = UnsafeMutablePointer<vorbis_dsp_state>.allocate(capacity: 1)
    private let block = UnsafeMutablePointer<vorbis_block>.allocate(capacity: 1)
    private let stream = UnsafeMutablePointer<ogg_stream_state>.allocate(capacity: 1)

    private let handle: FileHandle
    private let channels: Int
    private var isClosed = false

    init(
        url: URL,
        sampleRate: Double,
        channels: Int,
        bitrate: BitrateMode,
        tags: AudioProbe.Tags?
    ) throws {
        self.channels = channels

        vorbis_info_init(info)
        let setup: Int32
        switch bitrate {
        case .variable(let level):
            setup = vorbis_encode_init_vbr(
                info, Int(channels), Int(sampleRate),
                Self.vorbisQuality(forVariable: level)
            )
        case .constant(let kbps):
            // Vorbis плохо переносит жёсткий CBR, поэтому просим средний битрейт.
            var result = vorbis_encode_init(
                info, Int(channels), Int(sampleRate), -1, kbps * 1000, -1
            )
            if result != 0 {
                // У библиотеки нет готового шаблона под такое сочетание частоты,
                // числа каналов и битрейта — переходим на переменный битрейт
                // с ближайшим по смыслу качеством.
                vorbis_info_clear(info)
                vorbis_info_init(info)
                result = vorbis_encode_init_vbr(
                    info, Int(channels), Int(sampleRate),
                    Self.vorbisQuality(forKilobits: kbps)
                )
            }
            setup = result
        }
        guard setup == 0 else {
            vorbis_info_clear(info)
            throw ConversionError("Кодировщик Vorbis не принял параметры")
        }

        vorbis_comment_init(comment)
        if let tags {
            Self.apply(tags, to: comment)
        }

        vorbis_analysis_init(dsp, info)
        vorbis_block_init(dsp, block)
        ogg_stream_init(stream, Int32.random(in: 1...Int32.max))

        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ConversionError("Не удалось создать файл в папке экспорта")
        }
        handle = try FileHandle(forWritingTo: url)

        try writeHeaders()
    }

    deinit {
        if !isClosed {
            cleanup()
        }
        info.deallocate()
        comment.deallocate()
        dsp.deallocate()
        block.deallocate()
        stream.deallocate()
    }

    func write(_ buffer: UnsafeMutablePointer<Float>, frames: Int) throws {
        guard frames > 0 else { return }

        // Библиотека отдаёт свои буферы — раскладываем в них чередующийся поток по каналам.
        guard let planes = vorbis_analysis_buffer(dsp, Int32(frames)) else {
            throw ConversionError("Кодировщик Vorbis не выдал буфер")
        }
        for channel in 0..<channels {
            guard let plane = planes[channel] else { continue }
            var index = channel
            for frame in 0..<frames {
                plane[frame] = buffer[index]
                index += channels
            }
        }
        vorbis_analysis_wrote(dsp, Int32(frames))
        try pump()
    }

    func finish() throws {
        guard !isClosed else { return }
        isClosed = true

        vorbis_analysis_wrote(dsp, 0)
        try pump()

        var page = ogg_page()
        while ogg_stream_flush(stream, &page) != 0 {
            try write(page: page)
        }

        try handle.close()
        cleanup()
    }

    // MARK: - Внутреннее

    private func writeHeaders() throws {
        var identification = ogg_packet()
        var comments = ogg_packet()
        var codebooks = ogg_packet()

        vorbis_analysis_headerout(dsp, comment, &identification, &comments, &codebooks)
        ogg_stream_packetin(stream, &identification)
        ogg_stream_packetin(stream, &comments)
        ogg_stream_packetin(stream, &codebooks)

        // Заголовки обязаны занимать отдельные страницы, поэтому именно flush.
        var page = ogg_page()
        while ogg_stream_flush(stream, &page) != 0 {
            try write(page: page)
        }
    }

    private func pump() throws {
        var packet = ogg_packet()
        var page = ogg_page()

        while vorbis_analysis_blockout(dsp, block) == 1 {
            vorbis_analysis(block, nil)
            vorbis_bitrate_addblock(block)

            while vorbis_bitrate_flushpacket(dsp, &packet) == 1 {
                ogg_stream_packetin(stream, &packet)
                while ogg_stream_pageout(stream, &page) != 0 {
                    try write(page: page)
                    if ogg_page_eos(&page) != 0 { break }
                }
            }
        }
    }

    private func write(page: ogg_page) throws {
        if let header = page.header, page.header_len > 0 {
            try handle.write(contentsOf: Data(bytes: header, count: page.header_len))
        }
        if let body = page.body, page.body_len > 0 {
            try handle.write(contentsOf: Data(bytes: body, count: page.body_len))
        }
    }

    private func cleanup() {
        ogg_stream_clear(stream)
        vorbis_block_clear(block)
        vorbis_dsp_clear(dsp)
        vorbis_comment_clear(comment)
        vorbis_info_clear(info)
    }

    private static func apply(_ tags: AudioProbe.Tags, to comment: UnsafeMutablePointer<vorbis_comment>) {
        func add(_ key: String, _ value: String?) {
            guard let value else { return }
            vorbis_comment_add_tag(comment, key, value)
        }
        // Комментарии Vorbis всегда в UTF-8 — с кириллицей проблем нет.
        add("TITLE", tags.title)
        add("ARTIST", tags.artist)
        add("ALBUM", tags.album)
        add("DATE", tags.year)
        add("TRACKNUMBER", tags.track)
        add("GENRE", tags.genre)
        add("COMMENT", tags.comment)
    }
}
