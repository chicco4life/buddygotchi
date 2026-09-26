import AVFoundation
import BoopKit
import Foundation
@preconcurrency import Speech

/// Push-to-talk on the Mac's mic (ARCHITECTURE.md §3.8). The core says when:
/// `start` on `talk_on` or the Talk button, `stop` on release, the button
/// again, the 30 s limit or a dropped link. The transcript comes back once,
/// with whether you yelled (BEHAVIORS.md §3.3), and the audio is never kept.
/// Recognition runs on the Mac only.
final class SpeechListener: @unchecked Sendable {
    let engine = AVAudioEngine()
    let recognizer = SFSpeechRecognizer()
    var request: SFSpeechAudioBufferRecognitionRequest?
    var task: SFSpeechRecognitionTask?
    var best = ""
    /// How loud you've been so far; touched only on `queue`.
    var meter = YellMeter()
    var finish: ((String?, Bool) -> Void)?
    /// Between `start` and `stop`: whether the mic should be on.
    var wanted = false
    let log: (String) -> Void
    let queue = DispatchQueue(label: "boop.talk")

    init(log: @escaping (String) -> Void) {
        self.log = log
    }

    /// Asks for speech recognition, then the microphone, the first time
    /// either is needed (UX.md §6). `done` gets nil when both are allowed,
    /// otherwise why not. Any queue.
    func authorize(_ done: @escaping @Sendable (String?) -> Void) {
        let refused = "Allow Boop in System Settings → Privacy & Security → "
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { _ in self.authorize(done) }
            return
        default:
            done(refused + "Speech Recognition.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            done(nil)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in self.authorize(done) }
        default:
            done(refused + "Microphone.")
        }
    }

    /// Turns the mic on, asking for access first if it's the first time.
    /// `failed` gets why, if it can't. If `stop` comes first, while macOS is
    /// still asking, the mic never turns on.
    func start(failed: @escaping @Sendable (String) -> Void) {
        queue.async { [self] in
            wanted = true
            authorize { why in
                self.queue.async {
                    guard self.wanted else { return }
                    if let why {
                        self.wanted = false
                        failed(why)
                    } else if let why = self.begin() {
                        self.wanted = false
                        failed(why)
                    }
                }
            }
        }
    }

    /// On `queue`: starts the mic and recognition, or says why it can't.
    private func begin() -> String? {
        guard task == nil else { return nil }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return "On-device speech recognition isn't available on this Mac."
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        best = ""
        meter = YellMeter()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            request.append(buffer)
            // Only the level leaves this closure, never the samples.
            guard let samples = buffer.floatChannelData?[0], buffer.format.sampleRate > 0 else { return }
            let level = YellMeter.dbfs(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
            let ms = Double(buffer.frameLength) * 1000 / buffer.format.sampleRate
            self?.queue.async { self?.meter.add(dbfs: level, ms: ms) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            log("talk: can't start the mic: \(error)")
            input.removeTap(onBus: 0)
            self.request = nil
            return "The Mac's microphone couldn't start."
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.queue.async {
                if let result { self.best = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self.done() }
            }
        }
        return nil
    }

    /// Stops the mic and hands over what was heard, or nil if nothing was,
    /// and whether you yelled.
    func stop(_ finish: @escaping (String?, Bool) -> Void) {
        queue.async { [self] in
            wanted = false
            guard task != nil else {
                finish(nil, false)
                return
            }
            self.finish = finish
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            request?.endAudio()
            // The final result usually arrives within a second.
            queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.done() }
        }
    }

    func done() {
        guard let finish else { return }
        self.finish = nil
        task?.cancel()
        task = nil
        request = nil
        let words = best.trimmingCharacters(in: .whitespacesAndNewlines)
        let yelled = meter.yelled
        best = ""
        meter = YellMeter()
        finish(words.isEmpty ? nil : words, yelled)
    }
}
