import Foundation

// Служебная утилита для самопроверки: прогоняет один файл через движок Agave.
// selftest-cli <вход> <выход> <формат> [разрядность]

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(
        Data("использование: selftest-cli <вход> <выход> <формат> [16|24|32]\n".utf8)
    )
    exit(2)
}

guard let format = OutputFormat(rawValue: args[3]) else {
    FileHandle.standardError.write(Data("неизвестный формат: \(args[3])\n".utf8))
    exit(2)
}

var settings = ConversionSettings()
settings.format = format
settings.copyMetadata = false
if args.count > 4, let bits = Int(args[4]), let depth = BitDepth(rawValue: bits) {
    settings.bitDepth = depth
}

do {
    try Transcoder.convert(
        source: URL(fileURLWithPath: args[1]),
        destination: URL(fileURLWithPath: args[2]),
        settings: settings,
        onProgress: { _ in },
        isCancelled: { false }
    )
} catch {
    FileHandle.standardError.write(Data("ошибка: \(error.localizedDescription)\n".utf8))
    exit(1)
}
