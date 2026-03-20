import Foundation

struct AlignedTextSection: Identifiable, Hashable {
    let id: UUID
    let sourceText: String
    let translatedText: String

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}

enum ImageTranslateTextAlignment {
    static func sections(source: String, translation: String) -> [AlignedTextSection] {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSource.isEmpty, !trimmedTranslation.isEmpty else {
            return []
        }

        let sourceParagraphs = splitParagraphs(trimmedSource)
        let translatedParagraphs = splitParagraphs(trimmedTranslation)

        if sourceParagraphs.count > 1, sourceParagraphs.count == translatedParagraphs.count {
            return zip(sourceParagraphs, translatedParagraphs).map { sourceParagraph, translatedParagraph in
                AlignedTextSection(
                    sourceText: sourceParagraph,
                    translatedText: translatedParagraph
                )
            }
        }

        let sourceLines = splitLines(trimmedSource)
        let translatedLines = splitLines(trimmedTranslation)

        if shouldAlignByLine(sourceLines: sourceLines, translatedLines: translatedLines) {
            let count = max(sourceLines.count, translatedLines.count)
            return (0 ..< count).map { index in
                AlignedTextSection(
                    sourceText: sourceLines[safe: index] ?? "",
                    translatedText: translatedLines[safe: index] ?? ""
                )
            }
        }

        return [
            AlignedTextSection(
                sourceText: trimmedSource,
                translatedText: trimmedTranslation
            )
        ]
    }

    private static func shouldAlignByLine(
        sourceLines: [String],
        translatedLines: [String]
    ) -> Bool {
        guard sourceLines.count > 1, translatedLines.count > 1 else {
            return false
        }

        let countDifference = abs(sourceLines.count - translatedLines.count)
        return countDifference <= 2
            && max(sourceLines.count, translatedLines.count) <= 24
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var buffer: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if !buffer.isEmpty {
                    paragraphs.append(buffer.joined(separator: "\n"))
                    buffer.removeAll(keepingCapacity: true)
                }
                continue
            }

            buffer.append(line)
        }

        if !buffer.isEmpty {
            paragraphs.append(buffer.joined(separator: "\n"))
        }

        return paragraphs
    }

    private static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
