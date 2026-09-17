import AudioToolbox
import Foundation

/// Быстрое чтение заголовка файла: что за формат, сколько длится, какие теги.
enum AudioProbe {

    struct Info: Equatable {
        var formatLabel: String
        var sampleRate: Double
        var channels: Int
        var duration: Double?
        /// Формат, который CoreAudio не открывает, — нужен свой декодер.
        var requiresVorbisDecoding: Bool = false
    }

    struct Tags: Equatable {
        var title: String?
        var artist: String?
        var album: String?
        var year: String?
        var track: String?
        var genre: String?
        var comment: String?

        var isEmpty: Bool {
            title == nil && artist == nil && album == nil
                && year == nil && track == nil && genre == nil && comment == nil
        }
    }

    static func probe(_ url: URL) -> Info? {
        if VorbisDecoder.isVorbisFile(url), let info = VorbisDecoder.probe(url) {
            return info
        }
        return coreAudioProbe(url)
    }

    static func tags(_ url: URL) -> Tags? {
        if VorbisDecoder.isVorbisFile(url), let tags = VorbisDecoder.tags(url) {
            return tags
        }
        return coreAudioTags(url)
    }

    private static func coreAudioProbe(_ url: URL) -> Info? {
        guard let file = open(url) else { return nil }
        defer { AudioFileClose(file) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &asbd) == noErr else {
            return nil
        }

        var fileType: AudioFileTypeID = 0
        var typeSize = UInt32(MemoryLayout<AudioFileTypeID>.size)
        AudioFileGetProperty(file, kAudioFilePropertyFileFormat, &typeSize, &fileType)

        var duration: Float64 = 0
        var durationSize = UInt32(MemoryLayout<Float64>.size)
        let durationStatus = AudioFileGetProperty(
            file, kAudioFilePropertyEstimatedDuration, &durationSize, &duration
        )

        return Info(
            formatLabel: label(dataFormat: asbd.mFormatID, fileType: fileType),
            sampleRate: asbd.mSampleRate,
            channels: Int(asbd.mChannelsPerFrame),
            duration: durationStatus == noErr && duration > 0 ? duration : nil
        )
    }

    private static func coreAudioTags(_ url: URL) -> Tags? {
        guard let file = open(url) else { return nil }
        defer { AudioFileClose(file) }

        var size = UInt32(MemoryLayout<CFDictionary?>.size)
        var raw: CFDictionary?
        let status = withUnsafeMutablePointer(to: &raw) { pointer in
            AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, pointer)
        }
        guard status == noErr, let dictionary = raw as? [String: Any] else { return nil }

        func value(_ key: String) -> String? {
            guard let text = dictionary[key] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let tags = Tags(
            title: value(kAFInfoDictionary_Title),
            artist: value(kAFInfoDictionary_Artist),
            album: value(kAFInfoDictionary_Album),
            year: value(kAFInfoDictionary_Year),
            track: value(kAFInfoDictionary_TrackNumber),
            genre: value(kAFInfoDictionary_Genre),
            comment: value(kAFInfoDictionary_Comments)
        )
        return tags.isEmpty ? nil : tags
    }

    private static func open(_ url: URL) -> AudioFileID? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr else {
            return nil
        }
        return file
    }

    private static func label(dataFormat: AudioFormatID, fileType: AudioFileTypeID) -> String {
        switch dataFormat {
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatMPEGLayer2: return "MP2"
        case kAudioFormatMPEGLayer1: return "MP1"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD, kAudioFormatMPEG4AAC_Spatial:
            return "AAC"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatAC3, kAudioFormatEnhancedAC3: return "AC-3"
        case kAudioFormatAppleIMA4: return "IMA4"
        case kAudioFormatALaw: return "A-law"
        case kAudioFormatULaw: return "µ-law"
        case kAudioFormatLinearPCM:
            switch fileType {
            case kAudioFileWAVEType, kAudioFileRF64Type, kAudioFileBW64Type, kAudioFileWave64Type:
                return "WAV"
            case kAudioFileAIFFType, kAudioFileAIFCType: return "AIFF"
            case kAudioFileCAFType: return "CAF"
            default: return "PCM"
            }
        default:
            return fourCharacterCode(dataFormat)
        }
    }

    private static func fourCharacterCode(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF),
        ]
        let text = String(bytes: bytes, encoding: .macOSRoman) ?? "?"
        return text.trimmingCharacters(in: .whitespaces).uppercased()
    }
}
