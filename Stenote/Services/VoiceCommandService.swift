// VoiceCommandService.swift
// Stenote — replaces spoken command phrases with text equivalents,
// and (optionally) "<word> emoji" / "emoji <word>" with a fitting emoji.

import Foundation
import Observation

@MainActor
final class VoiceCommandService {
    static let shared = VoiceCommandService()

    // Punctuation / formatting commands. `appendToPrevWord` strips the space
    // before the trigger so "hello comma" → "hello,".
    private struct Command {
        let regex: NSRegularExpression
        let replacement: String
    }

    private let commands: [Command]
    private let emojiBeforeRegex: NSRegularExpression?
    private let emojiAfterRegex: NSRegularExpression?

    private init() {
        // Precompiled once (this runs on every confirmed streaming update, so we
        // must not recompile per call).
        func cmd(_ triggers: [String], _ replacement: String, appendToPrev: Bool) -> [Command] {
            triggers.compactMap { trigger in
                let escaped = NSRegularExpression.escapedPattern(for: trigger)
                let pattern = appendToPrev ? "\\s*\\b\(escaped)\\b" : "\\b\(escaped)\\b"
                guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
                return Command(regex: re, replacement: replacement)
            }
        }
        commands =
            cmd(["new line", "neue zeile"], "\n", appendToPrev: false)
            + cmd(["new paragraph", "neuer absatz"], "\n\n", appendToPrev: false)
            + cmd(["period", "punkt"], ".", appendToPrev: true)
            + cmd(["comma", "komma"], ",", appendToPrev: true)
            + cmd(["question mark", "fragezeichen"], "?", appendToPrev: true)
            + cmd(["exclamation mark", "ausrufezeichen"], "!", appendToPrev: true)
            + cmd(["colon", "doppelpunkt"], ":", appendToPrev: true)
            + cmd(["semicolon", "semikolon"], ";", appendToPrev: true)

        // Capture up to two words next to the "emoji"/"emojis" trigger so phrases
        // like "thumbs up emoji" resolve, while "big smile emoji" keeps "big".
        emojiBeforeRegex = try? NSRegularExpression(
            pattern: "((?:[\\p{L}]+\\s+){0,1}[\\p{L}]+)\\s+emojis?\\b", options: .caseInsensitive)
        emojiAfterRegex = try? NSRegularExpression(
            pattern: "\\bemojis?\\s+((?:[\\p{L}]+\\s+){0,1}[\\p{L}]+)", options: .caseInsensitive)
    }

    /// Apply whichever transforms the user has enabled. Idempotent (safe to run
    /// repeatedly on the growing confirmed transcript during streaming).
    func process(_ text: String) -> String {
        var result = text
        if SettingsStore.shared.enableVoiceCommands {
            for command in commands {
                let range = NSRange(result.startIndex..., in: result)
                result = command.regex.stringByReplacingMatches(
                    in: result, range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: command.replacement))
            }
        }
        if SettingsStore.shared.enableEmojiCommands {
            result = applyEmoji(result)
        }
        return result
    }

    // MARK: - Emoji

    private func applyEmoji(_ text: String) -> String {
        guard text.range(of: "emoji", options: .caseInsensitive) != nil else { return text }
        var result = text
        if let re = emojiBeforeRegex { result = replaceEmoji(result, regex: re, wordGroupIsLeading: true) }
        if let re = emojiAfterRegex { result = replaceEmoji(result, regex: re, wordGroupIsLeading: false) }
        return result
    }

    /// Replace matches of a "<phrase> emoji" / "emoji <phrase>" pattern with the
    /// resolved emoji, keeping any non-matching leading/trailing word intact.
    private func replaceEmoji(_ text: String, regex: NSRegularExpression, wordGroupIsLeading: Bool) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = text
        // Reverse so earlier match ranges stay valid as we mutate.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let phraseRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let phrase = String(result[phraseRange]).lowercased()
                .trimmingCharacters(in: .whitespaces)
            let words = phrase.split(separator: " ").map(String.init)

            if let emoji = Self.emojiMap[phrase] {
                // Whole captured phrase is a known emoji name.
                result.replaceSubrange(fullRange, with: emoji)
            } else if words.count == 2,
                      let emoji = Self.emojiMap[wordGroupIsLeading ? words[1] : words[0]] {
                // Only the adjacent word is the emoji; keep the other word.
                let kept = wordGroupIsLeading ? words[0] : words[1]
                let replacement = wordGroupIsLeading ? "\(kept) \(emoji)" : "\(emoji) \(kept)"
                result.replaceSubrange(fullRange, with: replacement)
            }
            // else: unknown word → leave the text untouched.
        }
        return result
    }

    /// Curated spoken-name → emoji map (on-device, no model). Keep focused on
    /// emoji people actually dictate; multi-word keys ("thumbs up") are matched
    /// before single words.
    static let emojiMap: [String: String] = [
        // faces
        "smile": "😊", "smiley": "😊", "happy": "😊", "grin": "😁", "laugh": "😂",
        "laughing": "😂", "lol": "😂", "joy": "😂", "wink": "😉", "cool": "😎",
        "sunglasses": "😎", "love": "😍", "heart eyes": "😍", "kiss": "😘",
        "tongue": "😛", "thinking": "🤔", "neutral": "😐", "sad": "😢", "cry": "😭",
        "crying": "😭", "angry": "😠", "mad": "😠", "scared": "😨", "shocked": "😲",
        "wow": "😲", "surprised": "😲", "sick": "🤢", "sleepy": "😴", "tired": "😴",
        "nerd": "🤓", "party": "🥳", "shush": "🤫", "pleading": "🥺", "screaming": "😱",
        "sweat": "😅", "salute": "🫡", "wink emoji": "😉",
        // gestures
        "thumbs up": "👍", "thumbsup": "👍", "thumbs down": "👎", "thumbsdown": "👎",
        "ok": "👌", "okay": "👌", "clap": "👏", "clapping": "👏", "wave": "👋",
        "waving": "👋", "pray": "🙏", "prayer": "🙏", "please": "🙏", "thanks": "🙏",
        "muscle": "💪", "strong": "💪", "flex": "💪", "fist": "👊", "punch": "👊",
        "peace": "✌️", "crossed fingers": "🤞", "raised hands": "🙌", "handshake": "🤝",
        // hearts & symbols
        "heart": "❤️", "red heart": "❤️", "broken heart": "💔", "sparkling heart": "💖",
        "fire": "🔥", "hundred": "💯", "star": "⭐", "sparkles": "✨", "check": "✅",
        "checkmark": "✅", "tick": "✅", "cross": "❌", "warning": "⚠️", "question": "❓",
        "exclamation": "❗", "idea": "💡", "bulb": "💡",
        // nature
        "sun": "☀️", "sunny": "☀️", "moon": "🌙", "cloud": "☁️", "rain": "🌧️",
        "rainy": "🌧️", "snow": "❄️", "snowman": "⛄", "lightning": "⚡", "thunder": "⚡",
        "rainbow": "🌈", "wave water": "🌊", "earth": "🌍", "world": "🌍", "globe": "🌍",
        "flower": "🌸", "rose": "🌹", "tree": "🌳", "leaf": "🍃",
        // animals
        "dog": "🐶", "cat": "🐱", "mouse": "🐭", "fox": "🦊", "bear": "🐻", "panda": "🐼",
        "lion": "🦁", "tiger": "🐯", "monkey": "🐵", "pig": "🐷", "frog": "🐸",
        "penguin": "🐧", "bird": "🐦", "unicorn": "🦄", "bug": "🐛", "butterfly": "🦋",
        "bee": "🐝", "snake": "🐍", "turtle": "🐢", "fish": "🐟", "dolphin": "🐬",
        "whale": "🐳", "octopus": "🐙",
        // food & drink
        "coffee": "☕", "beer": "🍺", "wine": "🍷", "pizza": "🍕", "burger": "🍔",
        "fries": "🍟", "cake": "🍰", "birthday cake": "🎂", "cookie": "🍪", "apple": "🍎",
        "banana": "🍌", "taco": "🌮", "bread": "🍞", "egg": "🥚", "cheese": "🧀",
        "avocado": "🥑", "pepper": "🌶️",
        // objects & activity
        "rocket": "🚀", "car": "🚗", "plane": "✈️", "airplane": "✈️", "train": "🚆",
        "bike": "🚲", "bicycle": "🚲", "ball": "⚽", "soccer": "⚽", "basketball": "🏀",
        "football": "🏈", "trophy": "🏆", "medal": "🏅", "gift": "🎁", "present": "🎁",
        "balloon": "🎈", "music": "🎵", "note": "🎵", "microphone": "🎤", "mic": "🎤",
        "camera": "📷", "phone": "📱", "computer": "💻", "laptop": "💻", "money": "💰",
        "dollar": "💰", "bell": "🔔", "lock": "🔒", "key": "🔑", "bomb": "💣",
        "skull": "💀", "ghost": "👻", "alien": "👽", "robot": "🤖", "poop": "💩",
        "eyes": "👀", "brain": "🧠", "clock": "⏰", "calendar": "📅", "book": "📚",
        "pencil": "✏️", "pen": "🖊️", "email": "📧", "mail": "📧", "hourglass": "⏳",
        "hammer": "🔨", "wrench": "🔧", "gear": "⚙️", "flag": "🚩",
    ]
}
