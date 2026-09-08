import SwiftUI

/// One fixture list drives art, popover and card coverage in both appearances.
struct CompanionScene {
    var name: String
    var creature: Creature
    var cosmetic = EquippedCosmetic()
    var needsPopover: Bool { creature.card != nil || creature.gift || creature.bubble != nil || creature.state == .uhoh }
    static let all: [Self] = {
        var scenes: [Self] = []
        for state in CreatureState.allCases {
            for cheer in CheerSize.allCases {
                var c = Creature.initial; c.state = state; c.cheer = cheer
                scenes.append(Self(name: "\(state.rawValue)-\(cheer.rawValue)", creature: c))
            }
        }
        for effort in CreatureEffort.allCases {
            var c = Creature.initial; c.state = .working; c.effort = effort
            scenes.append(Self(name: "effort-\(effort.rawValue)", creature: c))
        }
        for stakes in Stakes.allCases {
            var c = Creature.initial; c.state = .needsYou
            c.card = CreatureCard(id: "preview", tool: "Bash", gloss: "swift build", stakes: stakes, index: 0, count: 1, isApproval: true)
            scenes.append(Self(name: "stakes-\(stakes.rawValue)", creature: c))
        }
        for kind in UhohKind.allCases {
            var c = Creature.initial; c.state = .uhoh; c.uhoh = kind
            c.bubble = kind == .error ? "build failed" : kind == .stuck ? "might be going in circles" : "waiting for a refill"
            scenes.append(Self(name: "uhoh-\(kind.rawValue)", creature: c))
        }
        for level in 1...3 {
            var c = Creature.initial; c.state = .idle; c.overlay = .greet; c.greetLevel = level
            scenes.append(Self(name: "greet-\(level)", creature: c))
        }
        var boop = Creature.initial; boop.state = .idle; boop.overlay = .boop
        scenes.append(Self(name: "boop", creature: boop))
        for unlock in CosmeticUnlock.schedule where ["skin", "accessory", "silhouette"].contains(unlock.kind) {
            var cosmetic = EquippedCosmetic()
            switch unlock.kind { case "skin": cosmetic.skin = unlock.name; case "accessory": cosmetic.accessory = unlock.name; default: cosmetic.silhouette = unlock.name }
            var c = Creature.initial; c.state = .idle
            scenes.append(Self(name: "\(unlock.kind)-\(unlock.name)", creature: c, cosmetic: cosmetic))
        }
        var gift = Creature.initial; gift.state = .idle; gift.gift = true; gift.giftLine = "first one"
        scenes.append(Self(name: "gift", creature: gift))
        return scenes
    }()
}
