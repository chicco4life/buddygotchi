import Foundation

let spriteWidth = 14

private func normalize(_ line: String) -> String {
    let count = line.count
    if count == spriteWidth { return line }
    if count > spriteWidth { return String(line.prefix(spriteWidth)) }
    let pad = spriteWidth - count
    let left = pad / 2
    return String(repeating: " ", count: left) + line + String(repeating: " ", count: pad - left)
}

private func sprite(_ lines: [String]) -> [String] {
    lines.map(normalize)
}

struct BuddyStateAnim {
    let beatMs: Int
    let joinedPoses: [String]
    let seq: [Int]
    let overlay: String?

    init(beatMs: Int, poses: [[String]], seq: [Int], overlay: String?) {
        self.beatMs = beatMs
        self.joinedPoses = poses.map { $0.joined(separator: "\n") }
        self.seq = seq
        self.overlay = overlay
    }
}

struct BuddySpecies {
    let name: String
    let color: String
    let states: [String: BuddyStateAnim]

    subscript(state: String) -> BuddyStateAnim? { states[state] }
}

// MARK: - Cat

private let catStates: [String: BuddyStateAnim] = [
    "sleep": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "            ", "   .-..-.   ", "  ( -.- )   ", "  `------`~ "]),
        sprite(["            ", "            ", "   .-..-.   ", "  ( -.- )_  ", " `~------'~ "]),
        sprite(["            ", "            ", "   .-/\\.    ", "  (  ..  )) ", "  `~~~~~~`  "]),
        sprite(["            ", "            ", "   .-/\\.    ", "  (  ..  )) ", "  `~~~~~~`~ "]),
        sprite(["            ", "            ", "   .-..-.   ", "  ( u.u )   ", " `~------'~ "]),
        sprite(["            ", "            ", "   .-..-.   ", "  ( o.o )   ", "  `------`  "]),
    ], seq: [0,1,0,1,0,1, 3,3,0,1, 4,5,4,5,4,5, 2,2, 0,1,0,1, 5,5,4,4], overlay: "sleep"),
    "idle": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "   /\\_/\\    ", "  ( o   o ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  (o    o ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  ( o    o) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  ( -   - ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\-/\\    ", "  ( _   _ ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   <\\_/\\    ", "  ( o   o ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/>    ", "  ( o   o ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  ( o   o ) ", "  (  w   )  ", "  (\")_(\")~  "]),
        sprite(["            ", "   /\\_/\\    ", "  ( o   o ) ", "  (  w   )  ", " ~(\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  ( ^   ^ ) ", "  (  P   )  ", "  (\")_(\")   "]),
    ], seq: [0,0,0,3,0,1,0,2,0, 7,8,7,8,7, 0,5,0,6,0, 4,4,0, 9,9,9,0, 0,3,0, 8,7,8,7, 0,0,4,0], overlay: nil),
    "busy": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["      .     ", "   /\\_/\\    ", "  ( o   o ) ", "  (  w   )/ ", "  (\")_(\")   "]),
        sprite(["    .       ", "   /\\_/\\    ", "  ( o   o ) ", "  (  w   )_ ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  ( O   O ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["    o       ", "   /\\_/\\    ", "  ( o   o ) ", "  ( -w   )  ", "  (\")_(\")   "]),
        sprite(["  o         ", "   /\\_/\\    ", "  ( o   o ) ", "  (-w    )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /\\_/\\    ", "  ( -   - ) ", "  (  w   )  ", "  (\")_(\")   "]),
    ], seq: [2,2,2, 0,1,0,1, 3,4,3,4, 5,5, 2,2, 0,1,0,1, 5,2], overlay: "busy"),
    "attention": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "   /^_^\\    ", "  ( O   O ) ", "  (  v   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /^_^\\    ", "  (O    O ) ", "  (  v   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /^_^\\    ", "  ( O    O) ", "  (  v   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /^_^\\    ", "  ( ^   ^ ) ", "  (  v   )  ", "  (\")_(\")   "]),
        sprite(["            ", "   /^_^\\    ", " /( O   O )\\", " (   v    ) ", " /(\")_(\")\\ "]),
        sprite(["            ", "   /^_^\\    ", "  ( O   O ) ", "  (  >   )  ", "  (\")_(\")   "]),
    ], seq: [0,4,0,1,0,2,0,3, 4,4,0,1,2,0, 5,0], overlay: "attention"),
    "celebrate": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    \\o/     ", "   /\\_/\\    ", "  ( ^   ^ ) ", "  (  w   )  ", "  (\")_(\")   "]),
        sprite(["   * * *    ", "   /\\_/\\    ", "  ( ^   ^ ) ", " /(  w   )\\ ", "  (\")_(\")   "]),
        sprite(["  *  *  *   ", "   /\\_/\\    ", "  ( >   < ) ", "  (  P   )  ", " /(\")_(\")\\  "]),
        sprite(["    ***     ", "   /\\_/\\    ", "  ( ^   ^ ) ", "  (  w   )  ", "  (\")_(\")~  "]),
        sprite(["   *   *    ", "   /\\_/\\    ", "  ( ^   ^ ) ", "\\/(  w   )\\/", "  (\")_(\")   "]),
    ], seq: [0,1,2,3,4,0,1,2,3,4], overlay: nil),
]

// MARK: - Axolotl

private let axolotlStates: [String: BuddyStateAnim] = [
    "sleep": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "}~(______)~{", "}~( -  - )~{", "  ( .__. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~( _  _ )~{", "  ( .__. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "~}(______){~", "~}( _  _ ){~", "  ( ____ )  ", "  ~_/  \\_~  "]),
        sprite(["            ", "            ", "}~(.____.)~{", "}~(- __ -)~{", "  (__//__)  "]),
        sprite(["            ", "            ", "  }~~~~~_   ", " }~( -- -)= ", "  (__----)  "]),
        sprite(["            ", "}~(______)~{", "}~( o  o )~{", "  ( oOOo )  ", "  (_/  \\_)  "]),
    ], seq: [0,1,0,1,0,1,2,1, 0,1,0,1, 3,3,4,4,3,4, 3,3, 1,5,1,1], overlay: "sleep"),
    "idle": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "}~(______)~{", "}~( o  o )~{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~(o   o )~{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~( o   o)~{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~( ^  ^ )~{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~( -  - )~{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}}~(_____)~{", "}}~(o  o )~{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(_____)~{{", "}~(o  o )~{{", "  ( .--. )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~( o  o )~{", "  ( wwww )  ", "  (_/  \\_)  "]),
        sprite(["            ", "}~(______)~{", "}~( o  o )~{", "  ( WWWW )  ", "  (_/  \\_)  "]),
        sprite(["            ", "~}(______){~", "~}( o  o ){~", "  ( .--. )  ", "  ~_/  \\_~  "]),
    ], seq: [0,0,0,1,0,2,0,4, 0,5,0,6,0, 7,8,7,8, 0,0,3,3,0,4, 9,9,0,0, 1,2,1,2,0], overlay: nil),
    "busy": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "}~(______)~{", "}~( v  v )~{", "  (  --  )  ", " /(_/  \\_)\\ "]),
        sprite(["            ", "}~(______)~{", "}~( v  v )~{", "  (  __  )  ", " \\(_/  \\_)/ "]),
        sprite(["      ?     ", "}~(______)~{", "}~( ^  ^ )~{", "  (  ..  )  ", "  (_/  \\_)  "]),
        sprite(["      /     ", "}~(_____)~{ ", "}~( o  o )~{", "  ( .--. ) /", "  (_/  \\_)  "]),
        sprite(["      *     ", "}~(______)~{", "}~( O  O )~{", "  (  ^^  )  ", " /(_/  \\_)\\ "]),
        sprite(["    ~~~     ", "}~(______)~{", "}~( -  - )~{", "  (  __  )  ", "  (_/  \\_)  "]),
    ], seq: [0,1,0,1,0,1, 2,2, 0,1,0,1, 3,3, 2,4, 0,1,0,1,5], overlay: "busy"),
    "attention": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    ^  ^    ", "}}~(______)~{{", "}}~( O  O )~{{", "  (  O   )  ", "  (_/  \\_)  "]),
        sprite(["    ^  ^    ", "}}~(______)~{{", "}}~(O    O)~{{", "  (  O   )  ", "  (_/  \\_)  "]),
        sprite(["    ^  ^    ", "}}~(______)~{{", "}}~(O    O)~{{", "  (   O  )  ", "  (_/  \\_)  "]),
        sprite(["    ^  ^    ", "}}~(______)~{{", "}}~( ^  ^ )~{{", "  (  O   )  ", "  (_/  \\_)  "]),
        sprite(["    ^  ^    ", "}}}~(____)~{{{", "}}}~( O  O)~{{{", "  (  O   )  ", " /(_/  \\_)\\ "]),
        sprite(["    ^  ^    ", "}~(______)~{", "}~( o  o )~{", "  (  .   )  ", "  (_/  \\_)  "]),
    ], seq: [0,4,0,1,0,2,0,3, 4,4,0,1,2,0, 5,0], overlay: "attention"),
    "celebrate": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    \\o/     ", "}~(______)~{", "}~( ^  ^ )~{", "  ( >--< )  ", "  (_/  \\_)  "]),
        sprite(["   * * *    ", "}}~(_____)~{{", "}}~( ^  ^ )~{{", "  ( >--< )  ", " /(_/  \\_)\\ "]),
        sprite(["  *  *  *   ", "}~(______)~{", "}~( >  < )~{", "  ( WWWW )  ", "  (_/  \\_)  "]),
        sprite(["    ***     ", "~}(______){~", "~}( ^  ^ ){~", "  ( >--< )  ", "  ~_/  \\_~  "]),
        sprite(["   *   *    ", "}~(______)~{", "}~( ^  ^ )~{", "  ( >--< )  ", " \\(_/  \\_)/ "]),
    ], seq: [0,1,2,3,4,0,1,2,3,4], overlay: nil),
]

// MARK: - Robot

private let robotStates: [String: BuddyStateAnim] = [
    "sleep": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "   .[__].   ", "  [ -    - ]", "  [ ____ ]  ", "  `------'  "]),
        sprite(["            ", "   .[..].   ", "  [ .    . ]", "  [ ____ ]  ", "  `------'  "]),
        sprite(["            ", "   .[  ].   ", "  [        ]", "  [ ____ ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [ -    - ]", "  [ z__z ]  ", "  `------'  "]),
        sprite(["    .[*].   ", "   .[||].   ", "  [ -    - ]", "  [ zzzz ]  ", "  `------'  "]),
        sprite(["            ", "   .[..].   ", "  [ o    - ]", "  [ ____ ]  ", "  `------'  "]),
    ], seq: [0,1,2,1,0,1,2,1, 0,0,3,3, 4,4,4,3, 0,1,2,1,0, 5,0,1,0], overlay: "sleep"),
    "idle": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "   .[||].   ", "  [ o    o ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [o     o ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [ o     o]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [ -    - ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[\\\\].   ", "  [ o    o ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[//].   ", "  [ o    o ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [ o    o ]", "  [ -==- ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [ o    o ]", "  [ =--= ]  ", "  `------'  "]),
        sprite(["    .[*].   ", "   .[||].   ", "  [ ^    ^ ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["            ", "   .[||].   ", "  [ o    o ]", "  [ ==== ]  ", " /`------'\\ "]),
    ], seq: [0,0,1,1,0,2,2,0, 3,0,0, 4,5,4,5,0, 6,7,6,7,0, 0,8,8,0, 9,9,0,3,0], overlay: nil),
    "busy": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    01010   ", "   .[||].   ", "  [ #    # ]", "  [ ==== ]  ", " /`------'\\ "]),
        sprite(["    10101   ", "   .[||].   ", "  [ #    # ]", "  [ -==- ]  ", " \\`------'/ "]),
        sprite(["     ?      ", "   .[||].   ", "  [ ^    ^ ]", "  [ .... ]  ", "  `------'  "]),
        sprite(["    [@@]    ", "   .[||].   ", "  [ o    o ]", "  [ ==== ]  ", "  `------'  "]),
        sprite(["     !      ", "   .[||].   ", "  [ O    O ]", "  [ ^^^^ ]  ", " /`------'\\ "]),
        sprite(["    ~~~     ", "   .[||].   ", "  [ -    - ]", "  [ ____ ]  ", "  `------'  "]),
    ], seq: [0,1,0,1,0,1, 2,2, 0,1,0,1, 3,3, 2,4, 0,1,0,1, 5], overlay: "busy"),
    "attention": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    [!]     ", "   .[||].   ", "  [ O    O ]", "  [ #### ]  ", " /`------'\\ "]),
        sprite(["    [!]     ", "   .[\\\\].   ", "  [O     O ]", "  [ #### ]  ", " /`------'\\ "]),
        sprite(["    [!]     ", "   .[//].   ", "  [ O     O]", "  [ #### ]  ", " /`------'\\ "]),
        sprite(["    [!]     ", "   .[||].   ", "  [ ^    ^ ]", "  [ #### ]  ", " /`------'\\ "]),
        sprite(["    {!!}    ", "   .[||].   ", "  [ X    X ]", "  [ #### ]  ", "//`------'\\\\"]),
        sprite(["    [.]     ", "   .[||].   ", "  [ o    o ]", "  [ .... ]  ", "  `------'  "]),
    ], seq: [0,4,0,1,0,2,0,3, 4,4,0,1,2,0, 5,0], overlay: "attention"),
    "celebrate": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    [OK]    ", "   .[||].   ", "  [ ^    ^ ]", "  [ ^^^^ ]  ", " /`------'\\ "]),
        sprite(["   *[OK]*   ", "   .[\\\\].   ", "  [ ^    ^ ]", "  [ >>>> ]  ", " /`------'\\ "]),
        sprite(["  * [OK] *  ", "   .[//].   ", "  [ ^    ^ ]", "  [ ^^^^ ]  ", "//`------'\\\\"]),
        sprite(["    [OK]    ", "   .[||].   ", "  [ ^    ^ ]", "  [ ==== ]  ", " \\`------'/ "]),
        sprite(["   *[OK]*   ", "   .[||].   ", "  [ ^    ^ ]", "  [ >>>> ]  ", " /`------'\\ "]),
    ], seq: [0,1,2,3,4,0,1,2,3,4], overlay: nil),
]

// MARK: - Capybara

private let capybaraStates: [String: BuddyStateAnim] = [
    "sleep": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "            ", "    .--.    ", "  _( -- )_  ", " (___zz___) "]),
        sprite(["            ", "    .--.    ", "  _( -- )_  ", " (___..___) ", "  ~~~~~~~~  "]),
        sprite(["            ", "    .--.    ", "  _( __ )_  ", " (___oO___) ", "  ~~~~~~~~  "]),
        sprite(["            ", "            ", "  .---___   ", " (--   --)= ", "  `~~~~~~`  "]),
        sprite(["            ", "            ", "  .---___   ", " (-- ZZZ-)= ", "  `~~~~~~`  "]),
        sprite(["            ", "    .--.    ", "  _( ^^ )_  ", " (___O____) ", "  ~~~~~~~~  "]),
    ], seq: [0,1,0,1,0,1,2,1, 0,1,0,1, 3,4,3,4,3,4, 3,3, 1,5,1,1], overlay: "sleep"),
    "idle": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "  n______n  ", " ( o    o ) ", " (   oo   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " (o     o ) ", " (   oo   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " ( o     o) ", " (   oo   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " ( ^    ^ ) ", " (   oo   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " ( -    - ) ", " (   oo   ) ", "  `------'  "]),
        sprite(["            ", "  ^______n  ", " ( o    o ) ", " (   oo   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " ( o    o ) ", " (   ww   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " ( o    o ) ", " (   WW   ) ", "  `------'  "]),
        sprite(["            ", "  n______n  ", " ( -    - ) ", " (   OO   ) ", "  `------'  "]),
        sprite(["            ", " /n______n\\ ", "/( o    o )\\", " (   oo   ) ", "  `------'  "]),
    ], seq: [0,0,0,1,0,2,0,4, 0,5,0,0, 6,7,6,7, 0,0,3,3,0,4, 8,8,0,0, 9,9,0,0], overlay: nil),
    "busy": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "  n______n  ", " ( v    v ) ", " (   --   ) ", " /`------'\\ "]),
        sprite(["            ", "  n______n  ", " ( v    v ) ", " (   __   ) ", " \\`------'/ "]),
        sprite(["      ?     ", "  n______n  ", " ( ^    ^ ) ", " (   ..   ) ", "  `------'  "]),
        sprite(["    [_]     ", "  n_____|n  ", " ( o    o|) ", " (   --   ) ", "  `------'  "]),
        sprite(["      *     ", "  n______n  ", " ( O    O ) ", " (   ^^   ) ", " /`------'\\ "]),
        sprite(["    ~~~     ", "  n______n  ", " ( -    - ) ", " (   __   ) ", "  `------'  "]),
    ], seq: [0,1,0,1,0,1, 2,2, 0,1,0,1, 3,3, 2,4, 0,1,0,1,5], overlay: "busy"),
    "attention": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    ^  ^    ", " /^_____^\\  ", "( O      O )", " (   O    ) ", "  `------'  "]),
        sprite(["    ^  ^    ", " /^_____^\\  ", "(O       O )", " (   O    ) ", "  `------'  "]),
        sprite(["    ^  ^    ", " /^_____^\\  ", "( O       O)", " (   O    ) ", "  `------'  "]),
        sprite(["    ^  ^    ", " /^_____^\\  ", "( ^      ^ )", " (   O    ) ", "  `------'  "]),
        sprite(["    ^  ^    ", "/^^_____^^\\ ", "( O      O )", " (   O    ) ", " /`------'\\ "]),
        sprite(["    ^  ^    ", " /^_____^\\  ", "( o      o )", " (   .    ) ", "  `------'  "]),
    ], seq: [0,4,0,1,0,2,0,3, 4,4,0,1,2,0, 5,0], overlay: "attention"),
    "celebrate": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    \\o/     ", "  n______n  ", " ( ^    ^ ) ", " (   ^^   ) ", "  `------'  "]),
        sprite(["   * * *    ", " /n______n\\ ", "/( ^    ^ )\\", " (   WW   ) ", "  `------'  "]),
        sprite(["  *  *  *   ", "  n______n  ", " ( >    < ) ", " (   ww   ) ", " /`------'\\ "]),
        sprite(["    ***     ", "  n______n  ", " ( ^    ^ ) ", " (   ^^   ) ", "  `------'  "]),
        sprite(["   *   *    ", "  n______n  ", " ( ^    ^ ) ", " (   WW   ) ", " \\`------'/ "]),
    ], seq: [0,1,2,3,4,0,1,2,3,4], overlay: nil),
]

// MARK: - Dragon

private let dragonStates: [String: BuddyStateAnim] = [
    "sleep": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "            ", "   _____    ", "  (--   )~  ", "  `vvvvv'   "]),
        sprite(["            ", "            ", "   _____    ", "  (--   )~~ ", "  `vvvvv'   "]),
        sprite(["            ", "       o    ", "   _____    ", "  (--   )~~ ", "  `vvvvv'   "]),
        sprite(["            ", "  /v\\  /v\\  ", " <  --  -- >", " (        ) ", "  `-vvvv-'  "]),
        sprite(["            ", "  /^\\  /^\\  ", " <  oo  oo >", " (   __   ) ", "  `-vvvv-'  "]),
        sprite(["            ", "            ", "   _____    ", "  (--   )$  ", "  `vvvvv'$$ "]),
    ], seq: [0,1,0,1,0,1,2,1, 0,1,0,1, 3,4,3,4, 1,2,1, 5,5,0,0, 1,2,1,2], overlay: "sleep"),
    "idle": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["            ", "  /^\\  /^\\  ", " <  o    o >", " (   ww   ) ", "  `-vvvv-'  "]),
        sprite(["            ", "  /^\\  /^\\  ", " <o     o  >", " (   ww   ) ", "  `-vvvv-'  "]),
        sprite(["            ", "  /^\\  /^\\  ", " <  o     o>", " (   ww   ) ", "  `-vvvv-'  "]),
        sprite(["            ", "  /^\\  /^\\  ", " <  -    - >", " (   ww   ) ", "  `-vvvv-'  "]),
        sprite(["  /^\\  /^\\  ", "  \\_/  \\_/  ", " <  o    o >", " (   ww   ) ", "  `-vvvv-'  "]),
        sprite(["            ", "  \\v/  \\v/  ", " <  o    o >", " (   ww   ) ", "  `-vvvv-'  "]),
        sprite(["      ~     ", "  /^\\  /^\\  ", " <  o    o >", " (   nn   ) ", "  `-vvvv-'  "]),
        sprite(["         ~  ", "  /^\\  /^\\  ", " <  o    o >", " (   ww   )~", "  `-vvvv-'  "]),
        sprite(["            ", "  /^\\  /^\\  ", " <  ^    ^ >", " (   --   ) ", "  `-vvvv-'  "]),
        sprite(["  /^\\  /^\\  ", " //^\\  /^\\\\ ", "< <  o   o> >", "  (   ww  )  ", "   `-vvvv-'  "]),
    ], seq: [0,0,1,0,2,0,3, 4,5,4,5,4,5, 0,0,6,7, 0,3,0,8,8,0, 1,2,0, 9,9,0,0, 7,0,8,0], overlay: nil),
    "busy": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    $$$$    ", "  /^\\  /^\\  ", " <  v    v >", " (   --   ) ", " /`-vvvv-'\\ "]),
        sprite(["    $$$$    ", "  /^\\  /^\\  ", " <  v    v >", " (   __   ) ", " \\`-vvvv-'/ "]),
        sprite(["      ?     ", "  /^\\  /^\\  ", " <  ^    ^ >", " (   ..   ) ", "  `-vvvv-'  "]),
        sprite(["    [$]     ", "  /^|  /^\\  ", " <  v|   v >", " (   --   ) ", "  `-vvvv-'  "]),
        sprite(["      *     ", "  /^\\  /^\\  ", " <  O    O >", " (   ^^   )~", "  `-vvvv-'  "]),
        sprite(["    ~~~~    ", "  /^\\  /^\\  ", " <  -    - >", " (   __   ) ", "  `-vvvv-'  "]),
    ], seq: [0,1,0,1,0,1, 2,2, 0,1,0,1, 3,3, 2,4, 0,1,0,1,5], overlay: "busy"),
    "attention": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["    ^  ^    ", " /^^\\  /^^\\ ", "<  O    O  >", " (   <>   ) ", "  `-vvvv-'  "]),
        sprite(["    ^  ^    ", " /^^\\  /^^\\ ", "< O      O >", " (   O    ) ", "  `-vvvv-'  "]),
        sprite(["    ^  ^    ", " /^^\\  /^^\\ ", "<  O      O>", " (    O   ) ", "  `-vvvv-'  "]),
        sprite(["  ~~~  ~~~  ", " /^^\\  /^^\\ ", "<  O    O  >", " (   <>   )~", "  `-vvvv-'  "]),
        sprite(["    ^  ^    ", "/^^^\\  /^^^\\", "<  O    O  >", "((  <>   ))~", " /`-vvvv-'\\ "]),
        sprite(["    ^  ^    ", " /^^\\  /^^\\ ", "<  o    o  >", " (   ss   ) ", "  `-vvvv-'  "]),
    ], seq: [0,4,0,1,0,2,0,3, 4,4,0,1,2,3, 5,0], overlay: "attention"),
    "celebrate": BuddyStateAnim(beatMs: 200, poses: [
        sprite(["   $$$$$    ", "  /^^\\  /^^\\ ", " <  ^    ^  >", " (   <>   )~", "  `-vvvv-'  "]),
        sprite(["  * $$$ *   ", "  /^^\\  /^^\\ ", " <  ^    ^  >", "((   <>  )) ", " /`-vvvv-'\\ "]),
        sprite(["  $$ * $$   ", "  /^^\\  /^^\\ ", " <  >    <  >", " (   nn   )~", "  `-vvvv-'  "]),
        sprite(["   $$$$$    ", " /^^\\  /^^\\ ", "<  ^    ^  >", " (   <>   ) ", " \\`-vvvv-'/ "]),
        sprite(["  * $$$ *   ", "  /^^\\  /^^\\ ", " <  ^    ^  >", " (   <>   )~", "  `-vvvv-'  "]),
    ], seq: [0,1,2,3,4,0,1,2,3,4], overlay: nil),
]

// MARK: - Public API

let allBuddies: [String: BuddySpecies] = [
    "cat": BuddySpecies(name: "cat", color: "#c2a6ff", states: catStates),
    "axolotl": BuddySpecies(name: "axolotl", color: "#ffabbb", states: axolotlStates),
    "robot": BuddySpecies(name: "robot", color: "#c6c6d0", states: robotStates),
    "capybara": BuddySpecies(name: "capybara", color: "#d4a07a", states: capybaraStates),
    "dragon": BuddySpecies(name: "dragon", color: "#ff6b6b", states: dragonStates),
]

let buddyOrder = ["cat", "axolotl", "robot", "capybara", "dragon"]

func renderFrame(buddy: BuddySpecies, state: String, tickMs: Int) -> String {
    let anim = buddy[state] ?? buddy["idle"]!
    let idx = anim.seq[Int((tickMs / anim.beatMs)) % anim.seq.count]
    return anim.joinedPoses[idx]
}
