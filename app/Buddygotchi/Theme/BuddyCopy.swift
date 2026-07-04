enum BuddyCopy {
    enum Onboarding {
        static let hatchTitle = "Someone's been waiting for you."
        static let hatchSubtitle = "A little creature that watches your AI agents — and only bothers you when it matters."
        static let meetBuddy = "Meet your buddy"

        static let adoptTitle = "Adopt your buddy."
        static let nameLabel = "Name your buddy — optional"
        static let namePlaceholder = "Mochi"
        static let adopt = "Adopt"

        static let agentsTitle = "Connect your agents."
        static let agentsSubtitle = "Choose at least one agent so your buddy can hear it working."
        static let skipForNow = "Skip for now"
        static let connect = "Connect"
        static let connected = "Connected"
        static let detected = "Detected"
        static let notDetected = "Not detected"
        static let notDetectedHint = "haven't seen this agent on your Mac yet"
        static let hookInstallFailed = "couldn't write the hook — check permissions"

        static let firstContactTitle = "Wake it up."
        static let firstContactWaiting = "Open an agent and send any message."
        static let copyPrompt = "Copy a test prompt"
        static let testPrompt = "say hi to my buddygotchi"
        static let troubleshootingTitle = "Still listening."
        static let troubleshooting = "agent restarted since connecting? server running? port busy?"

        static let displayTitle = "Where your buddy lives."
        static let displaySubtitle = "You can change this later in settings."
        static let thisMac = "This Mac"
        static let thisMacDescription = "Your buddy lives in the menu bar."
        static let hardware = "Hardware buddy"
        static let hardwareDescription = "Pair over Bluetooth."
        static let hardwareFootnote = "works with an M5StickC Plus 2 today; the Buddygotchi hardware buddy hatches later this year."
        static let scanning = "Scanning for buddies…"
        static let connecting = "Connecting…"
        static let pairingHelp = "Check your buddy for a pairing code, then enter it on this Mac."
        static let pairingTimeout = "couldn't pair — hold the buddy closer and try again"
        static let connectedCheered = "Connected — your buddy just cheered."
        static let retry = "Try again"
        static let backToList = "Back to list"

        static let doneTitle = "Your buddy is ready."
        static let launchAtLogin = "Launch at login"
        static let launchAtLoginDescription = "Let your buddy wake up with your Mac."
        static let launchAtLoginUnavailable = "Available from the packaged app."
        static let notificationsTitle = "Let your buddy tap you on the shoulder."
        static let notificationsDescription = "One notification when an agent needs you."
        static let enableNotifications = "Enable notifications"
        static let notificationsEnabled = "Notifications enabled"
        static let startWatching = "Start watching"
        static let menuHint = "your buddy lives here now"
        static let finishMeeting = "Finish meeting your buddy."
        static let finishMeetingSubtitle = "The adoption window is ready when you are."
    }

    static let settings = "Settings"
    static let dismiss = "Dismiss"
    static let deny = "Deny"
    static let approve = "Approve"
    static let thinking = "Thinking"
    static let cancel = "Cancel"
    static let hide = "Hide"
    static let close = "Close"
    static let done = "Done"
    static let firmware = "Buddy firmware"
    static let updateNow = "Update now"
    static let updateComplete = "Update complete"
    static let updateFailed = "Update failed"
    static let tryAgain = "Try again"
    static let checkingForUpdates = "Checking for updates…"
    static let keepHardwareBuddyNear = "Keep your hardware buddy near your Mac and powered on. The update takes a few minutes; it will restart automatically when finished."
    static let previousFirmwareKept = "Your hardware buddy still runs the previous firmware — failed updates are not committed."
    static let runSetupAgain = "Run setup again"
    static let quitBuddygotchi = "Quit Buddygotchi"

    static let manifest: [String] = [
        Onboarding.hatchTitle,
        Onboarding.hatchSubtitle,
        Onboarding.meetBuddy,
        Onboarding.adoptTitle,
        Onboarding.nameLabel,
        Onboarding.namePlaceholder,
        Onboarding.adopt,
        Onboarding.agentsTitle,
        Onboarding.agentsSubtitle,
        Onboarding.skipForNow,
        Onboarding.connect,
        Onboarding.connected,
        Onboarding.detected,
        Onboarding.notDetected,
        Onboarding.notDetectedHint,
        Onboarding.hookInstallFailed,
        Onboarding.firstContactTitle,
        Onboarding.firstContactWaiting,
        Onboarding.copyPrompt,
        Onboarding.testPrompt,
        Onboarding.troubleshootingTitle,
        Onboarding.troubleshooting,
        Onboarding.displayTitle,
        Onboarding.displaySubtitle,
        Onboarding.thisMac,
        Onboarding.thisMacDescription,
        Onboarding.hardware,
        Onboarding.hardwareDescription,
        Onboarding.hardwareFootnote,
        Onboarding.scanning,
        Onboarding.connecting,
        Onboarding.pairingHelp,
        Onboarding.pairingTimeout,
        Onboarding.connectedCheered,
        Onboarding.retry,
        Onboarding.backToList,
        Onboarding.doneTitle,
        Onboarding.launchAtLogin,
        Onboarding.launchAtLoginDescription,
        Onboarding.launchAtLoginUnavailable,
        Onboarding.notificationsTitle,
        Onboarding.notificationsDescription,
        Onboarding.enableNotifications,
        Onboarding.notificationsEnabled,
        Onboarding.startWatching,
        Onboarding.menuHint,
        Onboarding.finishMeeting,
        Onboarding.finishMeetingSubtitle,
        settings,
        dismiss,
        deny,
        approve,
        thinking,
        cancel,
        hide,
        close,
        done,
        firmware,
        updateNow,
        updateComplete,
        updateFailed,
        tryAgain,
        checkingForUpdates,
        keepHardwareBuddyNear,
        previousFirmwareKept,
        runSetupAgain,
        quitBuddygotchi,
    ]

    static let allowedUppercaseWords: Set<String> = [
        "AI",
        "HTTP",
    ]
}
