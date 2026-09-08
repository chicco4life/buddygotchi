import Foundation

enum VoiceBanks {
    static let occasions = ["greet", "cheer_hop", "cheer_cheer", "cheer_dance", "uhoh_error", "uhoh_stuck", "uhoh_hungry", "recap", "profileLine", "hardWonPass", "redStreakEnded", "backAfterAbsence", "sameFileAgain", "lateNight", "nthRateLimit", "firstEver"]
    static func lines(language: String, occasion: String, register: VoiceRegister) -> [String] {
        banks[language + "/" + occasion]?[register.rawValue] ?? []
    }
    static let banks: [String: [String: [String]]] = {
        var result: [String: [String: [String]]] = [:]
        for language in ["en", "ko"] {
            for occasion in occasions {
                guard let url = Bundle.module.url(forResource: occasion, withExtension: "json", subdirectory: "voice/" + language),
                      let data = try? Data(contentsOf: url), let bank = try? JSONDecoder().decode([String: [String]].self, from: data) else { continue }
                result[language + "/" + occasion] = bank
            }
        }
        return result
    }()
    static func values(_ request: VoiceRequest) -> [String: String] {
        let ko = request.language == "ko"
        var facts: [String: String] = [:], runner: String?
        switch request.occasion {
        case .cheer(let moment, _, let name): facts = moment?.facts ?? [:]; runner = name
        case .uhoh(_, let moment): facts = moment?.facts ?? [:]
        case .recap(let recap): facts = ["n": String(recap.turns), "project": recap.project ?? ""]
        default: break
        }
        func label(_ value: String?, fallback: String) -> String {
            let value = (value ?? "").lowercased()
            guard !value.isEmpty, value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }),
                  VoiceFilter.check(value, language: request.language, byteCap: 63) != nil else { return fallback }
            return value.prefix(utf8Bytes: ko ? 6 : 8)
        }
        let subject = RunnerLabel.subject(runner ?? facts["runner"] ?? "")
        let localized = ko ? ["tests": "테스트", "build": "빌드", "lint": "린트"][subject ?? ""] : subject
        let count = Int(facts["attempts"] ?? facts["count"] ?? facts["n"] ?? "0") ?? 0
        return ["n": String(min(9999, max(0, count))),
                "runner": localized ?? (ko ? "확인" : "checks"),
                "project": label(facts["project"], fallback: ko ? "여기" : "project"),
                "agent": label(request.agent, fallback: ko ? "에이전트" : "agent"),
                "file": label(facts["path"], fallback: ko ? "파일" : "file")]
    }
    static func render(_ template: String, request: VoiceRequest) -> String {
        values(request).reduce(template) { $0.replacingOccurrences(of: "{" + $1.key + "}", with: $1.value) }
    }
}
