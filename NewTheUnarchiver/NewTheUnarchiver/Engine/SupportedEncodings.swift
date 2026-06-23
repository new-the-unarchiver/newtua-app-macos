import Foundation

/// One row in the inline encoding picker.
///
/// `label` is the WHATWG / `encoding_rs` identifier that the Rust engine
/// accepts verbatim via `Archive(path:, encoding:)`. `nil` means "let the
/// engine auto-detect" — the default for the picker's first entry.
/// `nameKey` is the String Catalog key for the display row.
struct SupportedEncoding: Hashable {
    let label: String?
    let nameKey: String
}

enum SupportedEncodings {
    static let auto = SupportedEncoding(label: nil, nameKey: "job.encoding.auto")

    /// Auto first, then UTF-8, then Cyrillic / Western / East-Asian families.
    /// The engine accepts any `encoding_rs` label — extend this list when
    /// users ask for more.
    static let all: [SupportedEncoding] = [
        auto,
        SupportedEncoding(label: "utf-8", nameKey: "job.encoding.utf8"),
        SupportedEncoding(label: "windows-1251", nameKey: "job.encoding.cp1251"),
        SupportedEncoding(label: "cp866", nameKey: "job.encoding.cp866"),
        SupportedEncoding(label: "windows-1252", nameKey: "job.encoding.cp1252"),
        SupportedEncoding(label: "iso-8859-1", nameKey: "job.encoding.iso88591"),
        SupportedEncoding(label: "iso-8859-2", nameKey: "job.encoding.iso88592"),
        SupportedEncoding(label: "shift_jis", nameKey: "job.encoding.shiftjis"),
        SupportedEncoding(label: "euc-jp", nameKey: "job.encoding.eucjp"),
        SupportedEncoding(label: "gbk", nameKey: "job.encoding.gbk"),
        SupportedEncoding(label: "big5", nameKey: "job.encoding.big5"),
        SupportedEncoding(label: "euc-kr", nameKey: "job.encoding.euckr"),
    ]
}
