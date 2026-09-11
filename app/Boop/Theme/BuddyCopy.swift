import Foundation
enum BuddyCopy {
    static let shared = Book()

    struct Book {
        var common = Common()
        let onboarding = OnboardingCopy()
        let settingsCopy = Settings()
        let popover = Popover()
        let firmwareUpdate = FirmwareUpdate()
        let notifications = Notifications()
        let appMenu = AppMenu()
    }

    private static let korean = Book(common: Common(language: "ko"))
    static func book(language: String) -> Book { language == "ko" ? korean : shared }

    struct Common {
        var language = "en"
        let appName = "Boop"
        var settings: String { language == "ko" ? "설정" : "Settings" }
        let dismiss = "Dismiss"
        var deny: String { language == "ko" ? "거부" : "Deny" }
        var approve: String { language == "ko" ? "허용" : "Approve" }
        let thinking = "Thinking"
        var cancel: String { language == "ko" ? "취소" : "Cancel" }
        let hide = "Hide"
        let close = "Close"
        let done = "Done"
        let ok = "OK"
        let unknown = "Unknown"
        let connect = "Connect"
        var connected: String { language == "ko" ? "연결됨" : "Connected" }
        let repair = "Repair"
        let firmware = "Buddy firmware"
        let updateNow = "Update now"
        let updateComplete = "Update complete"
        let updateFailed = "Update failed"
        let tryAgain = "Try again"
        let checkingForUpdates = "Checking for updates…"
        let keepHardwareBuddyNear = "Keep your hardware buddy near your Mac and powered on until the update finishes. The upload screen shows the estimated time remaining; your buddy will restart automatically."
        let checkInstalledFirmware = "Reconnect your hardware buddy to check its installed version before trying again."
        let runSetupAgain = "Run setup again"
        let quitBoop = "Quit Boop"
    }

    struct OnboardingCopy {
        let welcomeTitle = "Connect your Buddy."
        // Retired "a little creature", which implied one particular shape. The
        // form belongs to the device now.
        let welcomeSubtitle = "Connect your device and agents. Manage status, XP, and settings here."
        let meetBuddy = "Meet your buddy"

        let nameLabel = "Name your buddy — optional"
        let namePlaceholder = "Mochi"

        let agentsTitle = "Connect your agents."
        let agentsSubtitle = "Choose at least one agent so your buddy can hear it working."
        let skipForNow = "Skip for now"
        let connect = "Connect"
        let connected = "Connected"
        let detected = "Detected"
        let notDetected = "Not detected"
        let notDetectedHint = "haven’t seen this agent on your Mac yet"
        let hookInstallFailed = "couldn’t write the hook — check permissions"

        let firstContactTitle = "Wake it up."
        let firstContactWaiting = "Open an agent and send any message."
        let heardFromTemplate = "Heard from {agent}."
        let copyPrompt = "Copy a test prompt"
        let copied = "Copied"
        let testPrompt = "say hi to my boop"
        let troubleshootingTitle = "Still listening."
        let troubleshooting = "agent restarted since connecting? server running? port busy?"

        let displayTitle = "Where your buddy lives."
        let displaySubtitle = "You can change this later in settings."
        let thisMac = "This Mac"
        let thisMacDescription = "Your buddy lives in the menu bar."
        let hardware = "Hardware buddy"
        let hardwareDescription = "Pair over Bluetooth."
        let hardwareFootnote = "Works with any device running Boop firmware. Flash it first, then pair it here."
        let scanning = "Scanning for buddies…"
        let bluetoothOff = "Bluetooth is off"
        let bluetoothOffHint = "Turn on Bluetooth to find your buddy."
        let connecting = "Connecting…"
        let pairingHelp = "Check your buddy for a pairing code, then enter it on this Mac."
        let pairingTimeout = "couldn’t pair — hold the buddy closer and try again"
        let connectedCheered = "Connected — your buddy just cheered."
        let retry = "Try again"
        let backToList = "Back to list"

        let doneTitle = "Your buddy is ready."
        let launchAtLogin = "Launch at login"
        let launchAtLoginDescription = "Let your buddy wake up with your Mac."
        let launchAtLoginUnavailable = "Available from the packaged app."
        let notificationsTitle = "Let your buddy tap you on the shoulder."
        let notificationsDescription = "One notification when an agent needs you."
        let enableNotifications = "Enable notifications"
        let notificationsEnabled = "Notifications enabled"
        let startWatching = "Start watching"
        let menuHint = "Open Boop for status and settings."
        let finishMeeting = "Finish meeting your buddy."
        let finishMeetingSubtitle = "The adoption window is ready when you are."
        let back = "Back"
        let next = "Next"
        let skip = "Skip"
        let agents = "Agents"
        let display = "Display"
        let skipped = "Skipped"
        let progressTemplate = "Onboarding progress, step {current} of {total}"
    }

    struct Settings {
        let backToLiveView = "Back to live view"
        let general = "General"
        let launchAtLogin = "Launch at login"
        let launchAtLoginDescription = "Start Boop when you log in to your Mac."
        let launchAtLoginApproval = "Approve Boop in System Settings, Login Items."
        let interactiveMode = "Open for attention"
        let interactiveModeDescription = "Open the control center when an agent needs your attention."
        let sounds = "Sounds"
        let soundsDescription = "Play a short sound for attention, errors, and long completions."
        let localApprovalMode = "Approve through Buddy"
        let localApprovalModeSentence = "Move approvals to Buddy?"
        let localApprovalModeDescription = "Off by default. Keep approvals in your editor or agent unless you choose Buddy."
        let httpPort = "HTTP Port"
        let openConfigFolder = "Open config folder"
        let advanced = "Advanced"
        let buddy = "Buddy"
        let buddyName = "Buddy name"
        let name = "Name"
        let agents = "Agents"
        let notConnected = "Not connected"
        let needsRepairReasonTemplate = "Needs repair — {reason}"
        let needsRepairVersionTemplate = "Needs repair — v{a} to v{b}"
        let displays = "Displays"
        let active = "Active"
        let thisMacActive = "This Mac, active"
        let forget = "Forget"
        let forgetThisBuddyTitle = "Forget this buddy?"
        let forgetThisBuddy = "Forget this buddy"
        let forgetBuddyMessage = "Your hardware buddy can be paired again later."
        let notPaired = "Not paired"
        let pairABuddy = "Pair a buddy"
        let bareHardwareBuddy = "Bare hardware buddy"
        let flashItFirst = "Flash it first in Chrome or Edge."
        let connectToDeviceTemplate = "Connect to {device}"
        let firmware = "Firmware"
        let firmwareUnknown = "Unknown"
        let firmwareUpdateTemplate = "Update · {version}"
        let upToDate = "Up to date"
        let updating = "Updating…"
        let updated = "Updated"
        let failed = "Failed"
        let cantCheckNow = "Can’t check now"
        let checking = "Checking…"
        let firmwareAvailableTemplate = "Firmware {current}, update available to {next}"
        let firmwareUpToDateTemplate = "Firmware {current}, up to date"
        let firmwareUpdateInProgress = "Firmware update in progress"
        let firmwareUpdated = "Firmware updated"
        let firmwareUpdateFailed = "Firmware update failed"
        let firmwareCheckUnavailable = "Firmware update check unavailable"
        let checkingFirmwareUpdates = "Checking for firmware updates"
        let about = "About"
        let version = "Version"
        let checkForUpdates = "Check for updates"
        let helpAndSupport = "Help and support"
        let updatePrivacy = "Update checks read a static appcast. No analytics or device identifiers are sent."
        let exportBugReport = "Export bug report"
        let localPrivacy = "Boop keeps agent activity local to this Mac. Network access is limited to update checks and firmware downloads when those features are available."
        let removeBoop = "Remove Boop…"
        let exportBugReportFailed = "Couldn’t export bug report"
        let bugReportFallback = "The report could not be written."
        let removeBoopTitle = "Remove Boop?"
        let removeAndQuit = "Remove and quit"
        let removeBoopMessage = "This removes Boop hook entries from Claude Code, Cursor, and Codex, deletes ~/.boop, unregisters launch at login, clears notifications, and quits. Your app stays wherever you put it."
        let updatesUnavailable = "Updates unavailable"
        let updatesUnavailableMessage = "Automatic updates are available in the packaged app when Sparkle.framework is bundled."
        let removeFailed = "Could not remove Boop"
        let noDiagnosticData = "No diagnostic data was available."
        let desktopNotFound = "The Desktop folder could not be found."
        let desktopWriteFailedTemplate = "Couldn’t write to Desktop: {reason}"
        let server = "Server"
        let starting = "Starting"
        let listeningTemplate = "Listening on {port}"
        let failedReasonTemplate = "Failed — {reason}"
        let approvalExplainerRow1 = "Buddy can replace the native approval dialog for supported hooks; you may need to decide here instead of in your editor."
        let approvalExplainerRow2 = "Cursor read-only checks can be approved automatically. Shell commands and writes still ask first."
        let approvalExplainerRow3 = "If Boop is closed or unreachable, hooks fail open and the agent keeps its native flow."
        let turnOn = "Turn on"
    }

    struct Popover {
        let activeTemplate = "{count} active"
        let activeSessionsTemplate = "{count} active sessions"
        let desktopStatusTemplate = "Desktop {status}"
        let desktopStatusWithSessionsTemplate = "Desktop {status}, {sessions}"
        let serverWarningTemplate = "Can’t listen on port {port} — {reason}"
        let emptyAgents = "No agents awake. Open Claude Code, Cursor, or Codex and send a message — your buddy will hear it."
        let errorTrailerTemplate = "Also: {agent} hit an error"
        let moreWaitingTemplate = "+{count} more waiting"
        let moreSessionsTemplate = "+{count} more"
        let doneLabel = "done"
        let toolRequestTemplate = "Tool request: {tool}"
        let toolRequestWithHintTemplate = "Tool request: {tool}, {hint}"
        let workingTemplate = "Working: {message}"
        let completedTemplate = "Completed: {task}"
        let completedWithHintTemplate = "Completed: {task}, {hint}"
        let task = "task"
        let doneWithAgentTemplate = "Done · {agent}"
        let errorWithAgentTemplate = "Error · {agent}"
        let errorAccessibilityTemplate = "Error in {agent}"
        let errorAccessibilityWithToolTemplate = "Error in {agent}: {tool}"
        let errorAccessibilityWithHintTemplate = "Error in {agent}: {tool}, {hint}"
        let thinkingWithAgentTemplate = "Thinking · {agent}"
        let thinkingWithToolTemplate = "Thinking · {agent}, {tool}"
        let busy = "busy"
        let idle = "idle"
        let waiting = "waiting"
        let error = "error"
        let thinking = "thinking"
    }

    struct FirmwareUpdate {
        let downloading = "Downloading"
        let uploading = "Uploading"
        let verifying = "Verifying"
        let restartingDevice = "Restarting device"
        let phaseTemplate = "{phase}…"
        let stopUpdateTitle = "Stop the update?"
        let stopUpdate = "Stop update"
        let keepUpdating = "Keep updating"
        let keepCurrentFirmware = "Your buddy keeps its current firmware."
        let releasedTemplate = "released {date}"
        let updateServerUnavailable = "Couldn’t reach the update server — your buddy is fine."
        let aboutSecondsRemainingTemplate = "about {seconds}s remaining"
        let aboutMinutesRemainingTemplate = "about {minutes} min remaining"
    }

    struct Notifications {
        let titleTemplate = "{agent} needs you"
    }

    struct AppMenu {
        let openBoop = "Open Boop"
        let settings = "Settings…"
        let checkForUpdates = "Check for updates…"
        let quit = "Quit"
    }

    enum Onboarding {
        static var welcomeTitle: String { BuddyCopy.shared.onboarding.welcomeTitle }
        static var welcomeSubtitle: String { BuddyCopy.shared.onboarding.welcomeSubtitle }
        static var meetBuddy: String { BuddyCopy.shared.onboarding.meetBuddy }
        static var nameLabel: String { BuddyCopy.shared.onboarding.nameLabel }
        static var namePlaceholder: String { BuddyCopy.shared.onboarding.namePlaceholder }
        static var agentsTitle: String { BuddyCopy.shared.onboarding.agentsTitle }
        static var agentsSubtitle: String { BuddyCopy.shared.onboarding.agentsSubtitle }
        static var skipForNow: String { BuddyCopy.shared.onboarding.skipForNow }
        static var connect: String { BuddyCopy.shared.onboarding.connect }
        static var connected: String { BuddyCopy.shared.onboarding.connected }
        static var detected: String { BuddyCopy.shared.onboarding.detected }
        static var notDetected: String { BuddyCopy.shared.onboarding.notDetected }
        static var notDetectedHint: String { BuddyCopy.shared.onboarding.notDetectedHint }
        static var hookInstallFailed: String { BuddyCopy.shared.onboarding.hookInstallFailed }
        static var firstContactTitle: String { BuddyCopy.shared.onboarding.firstContactTitle }
        static var firstContactWaiting: String { BuddyCopy.shared.onboarding.firstContactWaiting }
        static var copyPrompt: String { BuddyCopy.shared.onboarding.copyPrompt }
        static var copied: String { BuddyCopy.shared.onboarding.copied }
        static var testPrompt: String { BuddyCopy.shared.onboarding.testPrompt }
        static var troubleshootingTitle: String { BuddyCopy.shared.onboarding.troubleshootingTitle }
        static var troubleshooting: String { BuddyCopy.shared.onboarding.troubleshooting }
        static var displayTitle: String { BuddyCopy.shared.onboarding.displayTitle }
        static var displaySubtitle: String { BuddyCopy.shared.onboarding.displaySubtitle }
        static var thisMac: String { BuddyCopy.shared.onboarding.thisMac }
        static var thisMacDescription: String { BuddyCopy.shared.onboarding.thisMacDescription }
        static var hardware: String { BuddyCopy.shared.onboarding.hardware }
        static var hardwareDescription: String { BuddyCopy.shared.onboarding.hardwareDescription }
        static var hardwareFootnote: String { BuddyCopy.shared.onboarding.hardwareFootnote }
        static var scanning: String { BuddyCopy.shared.onboarding.scanning }
        static var bluetoothOff: String { BuddyCopy.shared.onboarding.bluetoothOff }
        static var bluetoothOffHint: String { BuddyCopy.shared.onboarding.bluetoothOffHint }
        static var connecting: String { BuddyCopy.shared.onboarding.connecting }
        static var pairingHelp: String { BuddyCopy.shared.onboarding.pairingHelp }
        static var pairingTimeout: String { BuddyCopy.shared.onboarding.pairingTimeout }
        static var connectedCheered: String { BuddyCopy.shared.onboarding.connectedCheered }
        static var retry: String { BuddyCopy.shared.onboarding.retry }
        static var backToList: String { BuddyCopy.shared.onboarding.backToList }
        static var doneTitle: String { BuddyCopy.shared.onboarding.doneTitle }
        static var launchAtLogin: String { BuddyCopy.shared.onboarding.launchAtLogin }
        static var launchAtLoginDescription: String { BuddyCopy.shared.onboarding.launchAtLoginDescription }
        static var launchAtLoginUnavailable: String { BuddyCopy.shared.onboarding.launchAtLoginUnavailable }
        static var notificationsTitle: String { BuddyCopy.shared.onboarding.notificationsTitle }
        static var notificationsDescription: String { BuddyCopy.shared.onboarding.notificationsDescription }
        static var enableNotifications: String { BuddyCopy.shared.onboarding.enableNotifications }
        static var notificationsEnabled: String { BuddyCopy.shared.onboarding.notificationsEnabled }
        static var startWatching: String { BuddyCopy.shared.onboarding.startWatching }
        static var menuHint: String { BuddyCopy.shared.onboarding.menuHint }
        static var finishMeeting: String { BuddyCopy.shared.onboarding.finishMeeting }
        static var finishMeetingSubtitle: String { BuddyCopy.shared.onboarding.finishMeetingSubtitle }
    }

    static var settings: String { shared.common.settings }
    static var dismiss: String { shared.common.dismiss }
    static var deny: String { shared.common.deny }
    static var approve: String { shared.common.approve }
    static var thinking: String { shared.common.thinking }
    static var cancel: String { shared.common.cancel }
    static var hide: String { shared.common.hide }
    static var close: String { shared.common.close }
    static var done: String { shared.common.done }
    static var firmware: String { shared.common.firmware }
    static var updateNow: String { shared.common.updateNow }
    static var updateComplete: String { shared.common.updateComplete }
    static var updateFailed: String { shared.common.updateFailed }
    static var tryAgain: String { shared.common.tryAgain }
    static var checkingForUpdates: String { shared.common.checkingForUpdates }
    static var keepHardwareBuddyNear: String { shared.common.keepHardwareBuddyNear }
    static var checkInstalledFirmware: String { shared.common.checkInstalledFirmware }
    static var runSetupAgain: String { shared.common.runSetupAgain }
    static var quitBoop: String { shared.common.quitBoop }

    static func heardFrom(_ agentName: String) -> String {
        shared.onboarding.heardFromTemplate.replacingOccurrences(of: "{agent}", with: agentName)
    }

    static func notificationTitle(agentName: String) -> String {
        shared.notifications.titleTemplate.replacingOccurrences(of: "{agent}", with: agentName)
    }

    static func hookNeedsRepair(reason: String) -> String {
        shared.settingsCopy.needsRepairReasonTemplate.replacingOccurrences(of: "{reason}", with: reason)
    }

    static func hookNeedsRepair(installed: Int, current: Int) -> String {
        shared.settingsCopy.needsRepairVersionTemplate
            .replacingOccurrences(of: "{a}", with: "\(installed)")
            .replacingOccurrences(of: "{b}", with: "\(current)")
    }

    static let allowedUppercaseWords: Set<String> = [
        "AI",
        "HTTP",
    ]
}


extension BuddyCopy {
    static func growthLabel(_ growth: GrowthSnapshot, language: String = "en") -> String {
        String(format: phase7("growth", language: language), growth.xp, growth.streak)
    }
    static func momentPhrase(_ kind: String, language: String) -> String {
        guard Moment.Kind(rawValue: kind) != nil else { return phase7("noMoment", language: language) }
        return phase7(kind, language: language)
    }
    private static let phase7Table: [String: (String, String)] = [
        "codexApprovals": ("Handle Codex approvals in Boop", "Boop에서 Codex 승인 처리"),
        "codexApprovalsDescription": ("Keep Codex’s native review and approval flow by default. Opt in to intercept requests in Buddy; this can replace the Codex approval surface.", "기본적으로 꺼져 있어 Codex가 요청을 자동 검토합니다. 켜면 Codex의 일반 승인 절차 전에 Buddy에서 결정합니다."),
        "updatePrivacy": ("Update checks send no analytics or device identifiers.", "업데이트 확인 시 분석 데이터나 기기 식별자를 보내지 않아요."),
        "approvals": ("Approvals", "승인"),
        "agentsCan": ("Agents can", "에이전트 권한"),
        "diagnostics": ("Diagnostics", "진단"),
        "about": ("About", "정보"),
        "reset": ("Reset", "초기화"),
        "serverListening": ("Listening on 127.0.0.1:{port}", "127.0.0.1:{port}에서 수신 중"),
        "serverUnreachable": ("Not reachable", "연결할 수 없음"),
        "buddy": ("Buddy", "버디"), "agents": ("Agents", "에이전트"),
        "device": ("Device", "기기"), "advanced": ("Advanced", "고급"),
        "asleep": ("asleep", "잠자는 중"), "idle": ("idle", "대기 중"),
        "working": ("working", "작업 중"), "needsYou": ("needs you", "도움이 필요해요"),
        "done": ("done", "해냈어요"), "uhoh": ("uh-oh", "이런"),
        "noAgentsAwake": ("No agents awake", "깨어 있는 에이전트가 없어요"),
        "growth": ("%d XP · %d-day streak", "%d XP · %d일 연속"),
        "noMoment": ("A quiet day", "조용한 하루"),
        "device-connected": ("Device connected", "기기 연결됨"),
        "device-disconnected": ("Device disconnected", "기기 연결 끊김"),
        "device-connecting": ("Connecting", "연결 중"),
        "device-scanning": ("Scanning", "검색 중"),
        "shareDone": ("Done", "닫기"),
        "rankAll": ("All time", "전체"),
        "rankMonth": ("This month", "이번 달"),
        "rankFriends": ("Friends", "친구"),
        "yourRank": ("Your rank: %d", "내 순위: %d"),
        "friendsCodeLabel": ("Friends code: ", "친구 코드: "),
        "friendCode": ("Friend’s code", "친구 코드"),
        "addFriend": ("Add", "추가"),

            "hop": ("Hop", "폴짝"), "cheer": ("Cheer", "환호"), "dance": ("Dance", "춤"),
            "hardWonPass": ("A hard-won pass", "어렵게 이뤄낸 성공"), "redStreakEnded": ("Back on track", "다시 순조롭게"),
            "firstEver": ("First one", "첫 번째"), "backAfterAbsence": ("Welcome back", "돌아왔네요"),
            "sameFileAgain": ("One more little change", "작은 수정 하나 더"), "lateNight": ("A quiet night", "조용한 밤"),
            "fine": ("Fine", "괜찮아요"), "checkIt": ("Check it", "확인해 주세요"), "careful": ("Careful", "주의해 주세요"),
            "quietMode": ("Quiet mode", "무음 모드"), "quietModeDescription": ("Turn off Buddy’s sounds. Screen behavior stays the same.", "Buddy 소리를 끕니다. 화면 동작은 그대로 유지됩니다."), "focus": ("General", "일반"), "turns": ("Turns", "대화"), "tasks": ("Tasks", "작업"), "biggest": ("Biggest moment", "가장 큰 순간"),
            "profile": ("What your buddy knows", "버디가 알고 있는 것"), "emptyProfile": ("Still getting to know you.", "아직 알아가는 중이에요."),
            "clear": ("Forget everything", "모두 잊기"), "delete": ("Delete", "삭제"), "clearMessage": ("Your buddy’s name, level, and bond are kept. Only these profile lines are cleared.", "버디의 이름, 레벨, 유대감은 유지돼요. 이 프로필 내용만 지워져요."),
            "english": ("English", "English"), "korean": ("한국어", "한국어"),
            "language": ("Language", "언어"), "voice": ("Voice", "목소리"), "auto": ("Automatic", "자동"), "off": ("Off", "끄기"),
            "focusHours": ("Focus hours · daily", "매일 집중 시간"), "start": ("Start", "시작"), "end": ("End", "종료"),

            "volume": ("Volume", "음량"),
            "retire": ("Retire buddy", "버디 은퇴시키기"), "retireMessage": ("Say goodbye and begin again? This erases growth and everything your buddy learned.", "작별하고 다시 시작할까요? 성장 기록과 버디가 배운 모든 내용이 지워져요."),
            "name": ("Name your buddy", "버디 이름 짓기"), "namePermanent": ("A name to keep. You can’t change it later.", "오래 간직할 이름이에요. 나중에 바꿀 수 없어요."),
            "continue": ("Continue", "계속"),
            "disconnected": ("No device connected", "기기 연결 안 됨"),
            "error": ("Couldn't save this change. Please try again.", "변경을 저장하지 못했어요. 다시 시도해 주세요.")
        ]
    static func phase7(_ key: String, language: String) -> String {
        guard let pair = phase7Table[key] else { return key }
        return language == "ko" ? pair.1 : pair.0
    }
}
