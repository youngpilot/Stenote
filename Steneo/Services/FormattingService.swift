import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.youngpilot.Steneo", category: "Formatting")

/// How dictated text is STRUCTURED after cleanup. Distinct from `CleanupMode`
/// (which is lexical — filler removal): formatting reshapes the text and needs the
/// on-device LLM, so it's a separate opt-in. The user picks this in
/// Settings → Text Output → Format.
enum FormatMode: String, CaseIterable, Identifiable {
    case none        // leave structure as-is
    case paragraphs  // insert paragraph breaks at topic shifts (wording preserved)
    case bullets     // turn into a concise bullet list
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .paragraphs: return "Paragraphs"
        case .bullets: return "Bullets"
        }
    }
}

#if canImport(FoundationModels)
/// Guided-generation schema for paragraph reformatting — a typed field stops the
/// model from prepending commentary.
@available(macOS 26.0, *)
@Generable
struct FormattedText {
    @Guide(description: "The reformatted text only, in the same language as the input — no commentary, no preamble.")
    var text: String
}

/// Guided-generation schema for a bullet list — the model fills the items, the app
/// renders the bullet glyphs (consistent styling).
@available(macOS 26.0, *)
@Generable
struct BulletList {
    @Guide(description: "Each distinct point as one short bullet item, in the same language as the input. No numbering, no leading bullet characters.")
    var items: [String]
}
#endif

/// On-device structural formatting of dictated text via Apple's Foundation Models
/// (macOS 26+, Apple Intelligence). Runs AFTER cleanup, BEFORE paste. Never throws:
/// on any failure (unavailable, refusal, unsupported language, too long) it returns
/// the input unchanged. Everything stays on the Mac.
@MainActor
final class FormattingService {
    static let shared = FormattingService()
    private init() {}

    /// A mode-specific pre-warmed session (kept as AnyObject; `LanguageModelSession`
    /// is macOS 26+ only and this type deploys to 15.2).
    private var preparedBox: AnyObject?
    private var preparedMode: FormatMode?

    /// True when the on-device LLM is usable (so a format mode actually runs).
    var usesAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Warm a session for `mode` so formatting is fast at stop. Call on record-start
    /// when a format mode is active. No-op when unavailable or `.none`.
    func prewarm(mode: FormatMode) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), mode != .none, SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(instructions: Self.instructions(for: mode))
            session.prewarm()
            preparedBox = session
            preparedMode = mode
        }
        #endif
    }

    /// Reshape `text` per `mode`. Returns the input unchanged on `.none`, empty
    /// input, unavailable model, or any model failure.
    func format(_ text: String, mode: FormatMode) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode != .none, !trimmed.isEmpty else { return text }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let out = await formatWithModel(trimmed, mode: mode) { return out }
        }
        #endif
        return text   // no rules fallback for structure — leave the text as-is
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func formatWithModel(_ text: String, mode: FormatMode) async -> String? {
        let session = preparedSession(for: mode)
        preparedBox = nil; preparedMode = nil
        // Greedy = faithful (don't invent); bound output generously to the input size.
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: min(4000, max(256, text.count)))
        do {
            switch mode {
            case .paragraphs:
                let r = try await session.respond(to: text, generating: FormattedText.self, options: options)
                let out = r.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return Self.sane(out, against: text) ? out : nil
            case .bullets:
                let r = try await session.respond(to: text, generating: BulletList.self, options: options)
                let items = r.content.items
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !items.isEmpty else { return nil }
                let rendered = Self.renderBullets(items)
                return Self.sane(rendered, against: text) ? rendered : nil
            case .none:
                return nil
            }
        } catch {
            // Includes exceededContextWindowSize, unsupportedLanguageOrLocale,
            // guardrailViolation, refusal — all fall back to the unchanged input.
            logger.warning("Format model failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @available(macOS 26.0, *)
    private func preparedSession(for mode: FormatMode) -> LanguageModelSession {
        if preparedMode == mode, let s = preparedBox as? LanguageModelSession { return s }
        return LanguageModelSession(instructions: Self.instructions(for: mode))
    }

    private static func instructions(for mode: FormatMode) -> String {
        switch mode {
        case .paragraphs:
            return """
            You reformat raw dictated text by adding paragraph breaks. Keep EVERY word exactly as given, in the SAME language. Do not add, remove, translate, rephrase, summarize, answer, or comment. Only insert blank lines to separate distinct thoughts or topics into readable paragraphs. Output only the reformatted text.
            """
        case .bullets:
            return """
            You turn raw dictated text into a concise bullet list, in the SAME language. Split it into distinct points; each item captures one point in a short phrase, preserving the original wording and meaning as much as possible. Do not add new information, translate, answer, or comment. Output only the list items.
            """
        case .none:
            return ""
        }
    }
    #endif

    /// Render bullet items with a consistent glyph. Pure → unit-tested.
    static func renderBullets(_ items: [String]) -> String {
        items.map { "• " + $0 }.joined(separator: "\n")
    }

    /// Reject obvious misfires: empty, or wildly longer than the input (a sign the
    /// model added commentary instead of just restructuring).
    static func sane(_ out: String, against input: String) -> Bool {
        !out.isEmpty && out.count <= max(80, input.count * 3)
    }
}
