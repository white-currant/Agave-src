import AudioToolbox
import Foundation

/// Формат, в который конвертируем.
enum OutputFormat: String, CaseIterable, Identifiable, Codable {
    case mp3
    case aac
    case ogg
    case alac
    case flac
    case wav
    case aiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp3: return "MP3"
        case .aac: return "AAC"
        case .ogg: return "OGG"
        case .alac: return "ALAC"
        case .flac: return "FLAC"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        }
    }

    /// Пояснение в выпадающем меню.
    var subtitle: String {
        switch self {
        case .mp3: return "с потерями, совместим со всем"
        case .aac: return "с потерями, эффективнее MP3"
        case .ogg: return "с потерями, для игровых движков"
        case .alac: return "без потерь, формат Apple"
        case .flac: return "без потерь, открытый"
        case .wav: return "без сжатия"
        case .aiff: return "без сжатия, формат Apple"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .aac, .alac: return "m4a"
        case .ogg: return "ogg"
        case .flac: return "flac"
        case .wav: return "wav"
        case .aiff: return "aiff"
        }
    }

    var isLossy: Bool {
        self == .mp3 || self == .aac || self == .ogg
    }

    /// Формат поддерживает переменный битрейт по качеству.
    var supportsVariableBitrate: Bool {
        self == .mp3 || self == .ogg
    }

    /// У форматов без потерь настраивается разрядность, у остальных — битрейт.
    var availableBitDepths: [BitDepth] {
        switch self {
        case .mp3, .aac, .ogg: return []
        case .wav: return [.int16, .int24, .float32]
        case .aiff, .flac, .alac: return [.int16, .int24]
        }
    }

    var hasBitDepth: Bool {
        !availableBitDepths.isEmpty
    }

    /// Ближайшая поддерживаемая разрядность к выбранной пользователем.
    func resolvedBitDepth(_ requested: BitDepth) -> BitDepth {
        let available = availableBitDepths
        guard !available.isEmpty else { return requested }
        if available.contains(requested) { return requested }
        return available.min { lhs, rhs in
            abs(lhs.rawValue - requested.rawValue) < abs(rhs.rawValue - requested.rawValue)
        } ?? .int16
    }

    /// Тип файла-контейнера для ExtAudioFile.
    var audioFileType: AudioFileTypeID {
        switch self {
        case .mp3, .ogg: return 0 // пишутся сторонними кодировщиками
        case .aac, .alac: return kAudioFileM4AType
        case .flac: return kAudioFileFLACType
        case .wav: return kAudioFileWAVEType
        case .aiff: return kAudioFileAIFFType
        }
    }

    /// Максимум каналов, который формат осилит в нашей реализации.
    var maxChannels: Int {
        self == .mp3 ? 2 : 8
    }

    /// Потолок частоты дискретизации. MP3 и AAC выше 48 кГц не кодируются,
    /// Vorbis ограничений не имеет.
    var maxSampleRate: Double? {
        (self == .mp3 || self == .aac) ? 48000 : nil
    }
}

/// Битрейт для форматов с потерями.
enum BitrateMode: Hashable, Codable {
    /// Постоянный битрейт, кбит/с.
    case constant(Int)
    /// Переменный битрейт, качество 0 (лучшее) … 9.
    case variable(Int)

    static let constantChoices = [320, 256, 192, 160, 128, 96]
    static let variableChoices = [0, 2, 4]

    var title: String {
        switch self {
        case .constant(let kbps):
            return "\(kbps) кбит/с"
        case .variable(let quality):
            return "Переменный V\(quality)"
        }
    }

    var shortTitle: String {
        switch self {
        case .constant(let kbps): return "\(kbps)k"
        case .variable(let quality): return "V\(quality)"
        }
    }

    /// Примерный битрейт VBR-пресета — нужен, чтобы прикинуть размер и настроить AAC.
    var approximateKilobits: Int {
        switch self {
        case .constant(let kbps): return kbps
        case .variable(let quality):
            switch quality {
            case 0: return 245
            case 1: return 225
            case 2: return 190
            case 3: return 175
            case 4: return 165
            case 5: return 130
            case 6: return 115
            case 7: return 100
            case 8: return 85
            default: return 65
            }
        }
    }
}

/// Разрядность несжатых форматов.
enum BitDepth: Int, CaseIterable, Identifiable, Codable {
    case int16 = 16
    case int24 = 24
    case float32 = 32

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .int16: return "16 бит"
        case .int24: return "24 бита"
        case .float32: return "32 бита (float)"
        }
    }

    var isFloat: Bool { self == .float32 }
}

/// Частота дискретизации; `nil` — как в источнике.
enum SampleRateChoice: Int, CaseIterable, Identifiable, Codable {
    case source = 0
    case hz44100 = 44100
    case hz48000 = 48000
    case hz96000 = 96000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .source: return "Как в источнике"
        case .hz44100: return "44,1 кГц"
        case .hz48000: return "48 кГц"
        case .hz96000: return "96 кГц"
        }
    }

    var hertz: Double? {
        self == .source ? nil : Double(rawValue)
    }
}

/// Каналы; `nil` — как в источнике.
enum ChannelChoice: Int, CaseIterable, Identifiable, Codable {
    case source = 0
    case mono = 1
    case stereo = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .source: return "Как в источнике"
        case .mono: return "Моно"
        case .stereo: return "Стерео"
        }
    }

    var count: Int? {
        self == .source ? nil : rawValue
    }
}

/// Что делать, если файл с таким именем уже лежит в папке экспорта.
enum ConflictPolicy: String, CaseIterable, Identifiable, Codable {
    case rename
    case overwrite
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename: return "Добавить номер к имени"
        case .overwrite: return "Перезаписать"
        case .skip: return "Пропустить"
        }
    }
}

/// Полный набор параметров одной конвертации.
struct ConversionSettings: Equatable, Codable {
    var format: OutputFormat = .mp3
    var bitrate: BitrateMode = .constant(320)
    var bitDepth: BitDepth = .int16
    var sampleRate: SampleRateChoice = .source
    var channels: ChannelChoice = .source
    var conflict: ConflictPolicy = .rename
    var copyMetadata: Bool = true
}
