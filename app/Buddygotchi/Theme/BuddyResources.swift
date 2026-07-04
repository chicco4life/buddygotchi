import AppKit
import CoreText
import Foundation

enum BuddyResources {
    private static let moduleBundleName = "Buddygotchi_Buddygotchi.bundle"

    static func registerFonts() {
        for url in fontURLs() {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        #if DEBUG
        if NSFont(name: BuddyTheme.geistSemiBoldPostScriptName, size: 12) == nil {
            print("BUDDYGOTCHI WARNING: Geist SemiBold did not register; app typography is falling back.")
        }
        #endif
    }

    static func soundURL(_ name: String) -> URL? {
        resourceURL(forResource: name, withExtension: "caf", subdirectory: "Sounds")
            ?? resourceURL(forResource: name, withExtension: "wav", subdirectory: "Sounds")
    }

    static func moduleResourceURL(forResource name: String, withExtension ext: String, subdirectory: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
    }

    private static func fontURLs() -> [URL] {
        directoryCandidates(named: "Fonts").flatMap { directory in
            ((try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? [])
            .filter { ["otf", "ttf"].contains($0.pathExtension.lowercased()) }
        }
    }

    private static func resourceURL(forResource name: String, withExtension ext: String, subdirectory: String) -> URL? {
        if let url = moduleResourceURL(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }

        for directory in directoryCandidates(named: subdirectory) {
            let url = directory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func directoryCandidates(named directoryName: String) -> [URL] {
        var candidates: [URL] = []
        if let moduleDirectory = Bundle.module.url(forResource: directoryName, withExtension: nil) {
            candidates.append(moduleDirectory)
        }
        if let moduleResourceURL = Bundle.module.resourceURL {
            candidates.append(moduleResourceURL.appendingPathComponent(directoryName, isDirectory: true))
        }
        if let mainResourceURL = Bundle.main.resourceURL {
            candidates.append(mainResourceURL.appendingPathComponent(directoryName, isDirectory: true))
            candidates.append(
                mainResourceURL
                    .appendingPathComponent(moduleBundleName, isDirectory: true)
                    .appendingPathComponent(directoryName, isDirectory: true)
            )
        }
        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(
                executableDirectory
                    .appendingPathComponent(moduleBundleName, isDirectory: true)
                    .appendingPathComponent(directoryName, isDirectory: true)
            )
        }
        return candidates.uniqued()
    }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen = Set<String>()
        return filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
