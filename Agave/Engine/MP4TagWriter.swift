import AVFoundation
import Foundation

/// Проставляет теги в готовый файл MPEG-4 (AAC и ALAC).
///
/// `AudioFileSetProperty` для этого контейнера молча ничего не делает, поэтому
/// файл пересобирается сеансом экспорта в режиме passthrough: звук копируется
/// как есть, без повторного кодирования, и к нему добавляются теги.
enum MP4TagWriter {

    static func apply(_ tags: AudioProbe.Tags, to url: URL) {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough
        ) else { return }

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".agave-tag-\(UUID().uuidString).m4a")

        session.outputURL = temporaryURL
        session.outputFileType = .m4a
        session.metadata = items(from: tags)

        let semaphore = DispatchSemaphore(value: 0)
        session.exportAsynchronously { semaphore.signal() }
        semaphore.wait()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: temporaryURL)
            return
        }
        // Файл без тегов лучше, чем отсутствие файла: при неудаче замены
        // оставляем исходный результат конвертации нетронутым.
        if (try? FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)) == nil {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    private static func items(from tags: AudioProbe.Tags) -> [AVMetadataItem] {
        var result: [AVMetadataItem] = []

        func add(_ key: AVMetadataKey, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            let item = AVMutableMetadataItem()
            item.keySpace = .iTunes
            item.key = key.rawValue as NSString
            item.value = value as NSString
            result.append(item)
        }

        add(.iTunesMetadataKeySongName, tags.title)
        add(.iTunesMetadataKeyArtist, tags.artist)
        add(.iTunesMetadataKeyAlbum, tags.album)
        add(.iTunesMetadataKeyReleaseDate, tags.year)
        add(.iTunesMetadataKeyUserGenre, tags.genre)
        add(.iTunesMetadataKeyUserComment, tags.comment)
        add(.iTunesMetadataKeyTrackNumber, tags.track)

        return result
    }
}
