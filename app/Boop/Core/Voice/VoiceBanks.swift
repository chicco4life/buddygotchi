import Foundation

enum VoiceBanks {
    static let occasions = ["share", "greet", "recap", "recapParagraph", "profileLine"]
        + Moment.Kind.allCases.map(\.rawValue)
        + CheerSize.allCases.map { "cheer_" + $0.rawValue }
        + UhohKind.allCases.map { "uhoh_" + $0.rawValue }

    private static func load<T: Decodable>(_ name: String, language: String, as: T.Type) -> T? {
        guard let url = BuddyResources.moduleResourceURL(forResource: name, withExtension: "json", subdirectory: "voice/" + language),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static let banks: [String: [String: [String]]] = {
        var result: [String: [String: [String]]] = [:]
        for language in ["en", "ko"] {
            for occasion in occasions {
                result[language + "/" + occasion] = load(occasion, language: language, as: [String: [String]].self)
            }
        }
        return result
    }()
    static let leadIns = Dictionary(uniqueKeysWithValues: ["en", "ko"].map {
        ($0, load("leadIns", language: $0, as: [String: [String]].self) ?? [:])
    })
    private static let momentLabels = Dictionary(uniqueKeysWithValues: ["en", "ko"].map {
        ($0, load("momentLabels", language: $0, as: [String: String].self) ?? [:])
    })
    static func lines(language: String, occasion: String, register: VoiceRegister) -> [String] {
        banks[language + "/" + occasion]?[register.rawValue] ?? []
    }
    static func sanitizedLabel(_ value: String?, language: String, cap: Int, fallback: String) -> String {
        let value = (value ?? "").lowercased()
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }),
              let safe = VoiceFilter.check(value, language: language, byteCap: cap) else { return fallback }
        return safe
    }
    static func values(_ request: VoiceRequest) -> [String: String] {
        let ko = request.language == "ko", cap = request.isParagraph ? 48 : (request.language == "ko" ? 6 : 8)
        var facts: [String: String] = [:], runner: String?, moment: Moment.Kind?
        switch request.occasion {
        case .cheer(let value, _, let name): facts = value?.facts ?? [:]; runner = name; moment = value?.kind
        case .uhoh(_, let value): facts = value?.facts ?? [:]; moment = value?.kind
        case .recap(let recap):
            facts = ["n": String(recap.turns), "turns": String(recap.turns), "tasks": String(recap.tasks),
                     "openGoals": String(recap.openGoals), "hours": String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), recap.hours),
                     "project": recap.projectLabel(language: request.language, cap: cap)]
            moment = recap.biggestMoment
        default: break
        }
        let subject = RunnerLabel.subject(runner ?? facts["runner"] ?? "")
        let localized = ko ? ["tests": "테스트", "build": "빌드", "lint": "린트"][subject ?? ""] : subject
        let count = Int(facts["attempts"] ?? facts["count"] ?? facts["n"] ?? "0") ?? 0
        var values = ["n": String(min(9999, max(0, count))),
                      "runner": localized ?? (ko ? "확인" : "checks"),
                      "project": sanitizedLabel(facts["project"], language: request.language, cap: cap, fallback: ko ? "여기" : "project"),
                      "agent": sanitizedLabel(request.agent, language: request.language, cap: cap, fallback: ko ? "에이전트" : "agent"),
                      "file": sanitizedLabel(facts["path"], language: request.language, cap: cap, fallback: ko ? "파일" : "file"),
                      "momentKind": moment?.rawValue ?? "none"]
        for key in ["turns", "tasks", "openGoals", "hours"] { values[key] = facts[key] ?? "0" }
        return values
    }
    /// Seed chooses seasoning; callers enforce the cumulative 40% ceiling as well.
    static func render(_ template: String, request: VoiceRequest, values: [String: String], seed: UInt64 = 0, allowLeadIn: Bool = false) -> String {
        let leads = leadIns[request.language]?[request.register.rawValue] ?? []
        let lead = allowLeadIn && seed % 10 < 4 && !leads.isEmpty ? leads[Int((seed / 10) % UInt64(leads.count))] : ""
        var result = template
        if template.contains("{") {
            var replacements = values
            replacements["momentKind"] = momentLabels[request.language]?[values["momentKind"] ?? "none"] ?? ""
            replacements["leadIn"] = lead
            result = replacements.reduce(template) { $0.replacingOccurrences(of: "{" + $1.key + "}", with: $1.value) }
        }
        return template.contains("{leadIn}") ? result : lead + result
    }
    static func render(_ template: String, request: VoiceRequest) -> String {
        render(template, request: request, values: values(request))
    }
}
