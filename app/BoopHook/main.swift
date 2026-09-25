import Foundation

// The hook client. A1 connects it to the app's Unix socket. It must never
// print and must always exit 0, so a missing app never blocks an agent.
_ = FileHandle.standardInput.readDataToEndOfFile()
exit(0)
