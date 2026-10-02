import Foundation
import Testing
import SmartFanLocalization

@Suite("Localization coverage")
struct LocalizationCoverageTests {
    /// Every `language.text("…")` literal the app asks for must exist in the catalog.
    ///
    /// A missing key is not an error at runtime: it silently falls back to the English text,
    /// so a string edited in the catalog but not in the view (or the reverse) shows up as a
    /// caption that never translates — which is exactly what happened once here. The catalogs'
    /// own tests cannot catch it, because they only compare the catalogs with each other.
    @Test("Every literal a view asks for is in the catalog")
    func everyLiteralIsTranslated() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/SmartFanTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
        let catalog = try #require(LocalizationCatalog.bundled.translations[.english])

        let sources = root.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)

        var missing: [String] = []
        for file in files {
            for literal in Self.literals(in: try String(contentsOf: file, encoding: .utf8))
            where catalog[literal] == nil {
                missing.append("\(file.lastPathComponent): \(literal)")
            }
        }
        #expect(missing.isEmpty, "not in the catalog: \(missing.joined(separator: " | "))")
    }

    /// The first argument of every `.text(` call, when it is a plain literal. Keys built from
    /// a variable (the profile names, a tab's title key) are not literals and are covered by
    /// the catalogs' own tests.
    static func literals(in source: String) -> [String] {
        let pattern = #"\.text\(\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[captured])
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
    }

    @Test("The scanner finds literals and ignores everything else")
    func scanner() {
        let source = """
        Text(language.text("Fan {index}"))
        Text(language.text(item.titleKey))
        Text(language.text("He said \\"hi\\""))
        let label = language.text("CPU")
        """
        #expect(Self.literals(in: source) == ["Fan {index}", "He said \"hi\"", "CPU"])
    }
}
