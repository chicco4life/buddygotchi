enum BuddyCopy {
    static let shared = Book()

    struct Book {
        let common = Common()
        let onboarding = OnboardingCopy()
        let settingsCopy = Settings()
        let popover = Popover()
        let firmwareUpdate = FirmwareUpdate()
        let notifications = Notifications()
        let appMenu = AppMenu()
    }

    struct Common {
        let appName = "Buddygotchi"
        let settings = "Settings"
        let dismiss = "Dismiss"
        let deny = "Deny"
        let approve = "Approve"
        let thinking = "Thinking"
        let cancel = "Cancel"
        let hide = "Hide"
        let close = "Close"
        let done = "Done"
        let ok = "OK"
        let unknown = "Unknown"
        let connect = "Connect"
        let connected = "Connected"
        let repair = "Repair"
        let firmware = "Buddy firmware"
        let updateNow = "Update now"
        let updateComplete = "Update complete"
        let updateFailed = "Update failed"
        let tryAgain = "Try again"
        let checkingForUpdates = "Checking for updates…"
        let keepHardwareBuddyNear = "Keep your hardware buddy near your Mac and powered on. The update takes a few minutes; it will restart automatically when finished."
        let previousFirmwareKept = "Your hardware buddy still runs the previous firmware — failed updates are not committed."
        let runSetupAgain = "Run setup again"
        let quitBuddygotchi = "Quit Buddygotchi"
    }

    struct OnboardingCopy {
        let hatchTitle = "Someone's been waiting for you."
        let hatchSubtitle = "A little creature that watches your AI agents — and only bothers you when it matters."
        let meetBuddy = "Meet your buddy"

        let adoptTitle = "Adopt your buddy."
        let nameLabel = "Name your buddy — optional"
        let namePlaceholder = "Mochi"
        let adopt = "Adopt"

        let agentsTitle = "Connect your agents."
        let agentsSubtitle = "Choose at least one agent so your buddy can hear it working."
        let skipForNow = "Skip for now"
        let connect = "Connect"
        let connected = "Connected"
        let detected = "Detected"
        let notDetected = "Not detected"
        let notDetectedHint = "haven't seen this agent on your Mac yet"
        let hookInstallFailed = "couldn't write the hook — check permissions"

        let firstContactTitle = "Wake it up."
        let firstContactWaiting = "Open an agent and send any message."
        let heardFromTemplate = "Heard from {agent}."
        let copyPrompt = "Copy a test prompt"
        let testPrompt = "say hi to my buddygotchi"
        let troubleshootingTitle = "Still listening."
        let troubleshooting = "agent restarted since connecting? server running? port busy?"

        let displayTitle = "Where your buddy lives."
        let displaySubtitle = "You can change this later in settings."
        let thisMac = "This Mac"
        let thisMacDescription = "Your buddy lives in the menu bar."
        let hardware = "Hardware buddy"
        let hardwareDescription = "Pair over Bluetooth."
        let hardwareFootnote = "works with an M5StickC Plus 2 today; the Buddygotchi hardware buddy hatches later this year."
        let scanning = "Scanning for buddies…"
        let connecting = "Connecting…"
        let pairingHelp = "Check your buddy for a pairing code, then enter it on this Mac."
        let pairingTimeout = "couldn't pair — hold the buddy closer and try again"
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
        let menuHint = "your buddy lives here now"
        let finishMeeting = "Finish meeting your buddy."
        let finishMeetingSubtitle = "The adoption window is ready when you are."
        let back = "Back"
        let next = "Next"
        let skip = "Skip"
        let species = "Species"
        let agents = "Agents"
        let display = "Display"
        let skipped = "Skipped"
        let previousSpecies = "Previous species"
        let nextSpecies = "Next species"
        let progressTemplate = "Onboarding progress, step {current} of {total}"
        let buddyPreviewTemplate = "{species} buddy preview, {state}"
    }

    struct Settings {
        let backToLiveView = "Back to live view"
        let general = "General"
        let launchAtLogin = "Launch at Login"
        let launchAtLoginDescription = "Start Buddygotchi when you log in to your Mac."
        let launchAtLoginApproval = "Approve Buddygotchi in System Settings, Login Items."
        let interactiveMode = "Interactive Mode"
        let interactiveModeDescription = "Auto-show when your buddy celebrates or needs attention."
        let sounds = "Sounds"
        let soundsDescription = "Play a short sound for attention, errors, and long completions."
        let localApprovalMode = "Local Approval Mode"
        let localApprovalModeSentence = "Local approval mode"
        let localApprovalModeDescription = "Route tool approvals through Buddygotchi instead of your agent's built-in dialog."
        let httpPort = "HTTP Port"
        let openConfigFolder = "Open config folder"
        let advanced = "Advanced"
        let buddy = "Buddy"
        let buddyName = "Buddy name"
        let name = "Name"
        let speciesPickerTemplate = "Species picker, {species}, {current} of {total}"
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
        let checking = "Checking…"
        let firmwareAvailableTemplate = "Firmware {current}, update available to {next}"
        let firmwareUpToDateTemplate = "Firmware {current}, up to date"
        let firmwareUpdateInProgress = "Firmware update in progress"
        let firmwareUpdated = "Firmware updated"
        let firmwareUpdateFailed = "Firmware update failed"
        let checkingFirmwareUpdates = "Checking for firmware updates"
        let about = "About"
        let version = "Version"
        let checkForUpdates = "Check for updates"
        let helpAndSupport = "Help and support"
        let updatePrivacy = "Update checks read a static appcast. No analytics or device identifiers are sent."
        let exportBugReport = "Export bug report"
        let localPrivacy = "Buddygotchi keeps agent activity local to this Mac. Network access is limited to update checks and firmware downloads when those features are available."
        let removeBuddygotchi = "Remove Buddygotchi…"
        let exportBugReportFailed = "Couldn't export bug report"
        let bugReportFallback = "The report could not be written."
        let removeBuddygotchiTitle = "Remove Buddygotchi?"
        let removeAndQuit = "Remove and quit"
        let removeBuddygotchiMessage = "This removes Buddygotchi hook entries from Claude Code, Cursor, and Codex, deletes ~/.buddygotchi, unregisters launch at login, clears notifications, and quits. Your app stays wherever you put it."
        let updatesUnavailable = "Updates unavailable"
        let updatesUnavailableMessage = "Automatic updates are available in the packaged app when Sparkle.framework is bundled."
        let removeFailed = "Could not remove Buddygotchi"
        let noDiagnosticData = "No diagnostic data was available."
        let desktopNotFound = "The Desktop folder could not be found."
        let desktopWriteFailedTemplate = "Couldn't write to Desktop: {reason}"
        let server = "Server"
        let starting = "Starting"
        let listeningTemplate = "Listening on {port}"
        let failedReasonTemplate = "Failed — {reason}"
        let approvalExplainerRow1 = "Buddygotchi becomes the approval surface for supported hooks."
        let approvalExplainerRow2 = "Cursor read-only checks can be approved automatically. Shell commands and writes still ask first."
        let approvalExplainerRow3 = "If Buddygotchi is closed or unreachable, hooks fail open and the agent keeps its native flow."
        let turnOn = "Turn on"
    }

    struct Popover {
        let activeTemplate = "{count} active"
        let activeSessionsTemplate = "{count} active sessions"
        let desktopStatusTemplate = "Desktop {status}"
        let desktopStatusWithSessionsTemplate = "Desktop {status}, {sessions}"
        let serverWarningTemplate = "Can't listen on port {port} — {reason}"
        let emptyAgents = "No agents awake. Open Claude Code, Cursor, or Codex and send a message — your buddy will hear it."
        let errorTrailerTemplate = "Also: {agent} hit an error"
        let moreWaitingTemplate = "+{count} more waiting"
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
        let aboutSecondsRemainingTemplate = "about {seconds}s remaining"
        let aboutMinutesRemainingTemplate = "about {minutes} min remaining"
    }

    struct Notifications {
        let titleTemplate = "{agent} needs you"
    }

    struct AppMenu {
        let openBuddygotchi = "Open Buddygotchi"
        let settings = "Settings…"
        let checkForUpdates = "Check for updates…"
        let quit = "Quit"
    }

    enum Onboarding {
        static var hatchTitle: String { BuddyCopy.shared.onboarding.hatchTitle }
        static var hatchSubtitle: String { BuddyCopy.shared.onboarding.hatchSubtitle }
        static var meetBuddy: String { BuddyCopy.shared.onboarding.meetBuddy }
        static var adoptTitle: String { BuddyCopy.shared.onboarding.adoptTitle }
        static var nameLabel: String { BuddyCopy.shared.onboarding.nameLabel }
        static var namePlaceholder: String { BuddyCopy.shared.onboarding.namePlaceholder }
        static var adopt: String { BuddyCopy.shared.onboarding.adopt }
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
    static var previousFirmwareKept: String { shared.common.previousFirmwareKept }
    static var runSetupAgain: String { shared.common.runSetupAgain }
    static var quitBuddygotchi: String { shared.common.quitBuddygotchi }

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
