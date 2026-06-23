// VoiceCommandService.swift
// Stenote — replaces spoken command phrases with text equivalents

import Foundation
import Observation

struct VoiceCommand {
    let triggers: [String]
    let replacement: String
    let appendToPrevWord: Bool
}

@Observable
@MainActor
final class VoiceCommandService {
    static let shared = VoiceCommandService()

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "enableVoiceCommands") }
    }

    private let commands: [VoiceCommand] = [
        VoiceCommand(triggers: ["new line", "neue zeile"], replacement: "\n", appendToPrevWord: false),
        VoiceCommand(triggers: ["new paragraph", "neuer absatz"], replacement: "\n\n", appendToPrevWord: false),
        VoiceCommand(triggers: ["period", "punkt"], replacement: ".", appendToPrevWord: true),
        VoiceCommand(triggers: ["comma", "komma"], replacement: ",", appendToPrevWord: true),
        VoiceCommand(triggers: ["question mark", "fragezeichen"], replacement: "?", appendToPrevWord: true),
        VoiceCommand(triggers: ["exclamation mark", "ausrufezeichen"], replacement: "!", appendToPrevWord: true),
        VoiceCommand(triggers: ["colon", "doppelpunkt"], replacement: ":", appendToPrevWord: true),
        VoiceCommand(triggers: ["semicolon", "semikolon"], replacement: ";", appendToPrevWord: true),
    ]

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "enableVoiceCommands") as? Bool ?? false
    }

    func process(_ text: String) -> String {
        guard isEnabled else { return text }

        var result = text

        for command in commands {
            for trigger in command.triggers {
                let pattern: String
                if command.appendToPrevWord {
                    pattern = "\\s+\\b\(NSRegularExpression.escapedPattern(for: trigger))\\b"
                } else {
                    pattern = "\\b\(NSRegularExpression.escapedPattern(for: trigger))\\b"
                }

                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    continue
                }

                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: command.replacement)
            }
        }

        return result
    }
}
