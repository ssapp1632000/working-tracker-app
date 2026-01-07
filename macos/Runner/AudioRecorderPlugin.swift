import Cocoa
import FlutterMacOS
import AVFoundation

class AudioRecorderPlugin: NSObject, FlutterPlugin, AVAudioRecorderDelegate {
    private var audioRecorder: AVAudioRecorder?
    private var currentFilePath: String?
    private var channel: FlutterMethodChannel?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.silverstone.audio_recorder",
            binaryMessenger: registrar.messenger
        )
        let instance = AudioRecorderPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            if let args = call.arguments as? [String: Any],
               let path = args["path"] as? String {
                startRecording(path: path, result: result)
            } else {
                result(FlutterError(code: "INVALID_ARGS", message: "Path is required", details: nil))
            }
        case "stopRecording":
            stopRecording(result: result)
        case "isRecording":
            result(audioRecorder?.isRecording ?? false)
        case "hasPermission":
            checkPermission(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func checkPermission(result: @escaping FlutterResult) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            result(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    result(granted)
                }
            }
        case .denied, .restricted:
            result(false)
        @unknown default:
            result(false)
        }
    }

    private func startRecording(path: String, result: @escaping FlutterResult) {
        // Stop any existing recording
        if audioRecorder?.isRecording == true {
            audioRecorder?.stop()
            audioRecorder = nil
        }

        currentFilePath = path
        let url = URL(fileURLWithPath: path)

        // Ensure the directory exists
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("AudioRecorderPlugin: Failed to create directory: \(error.localizedDescription)")
            result(FlutterError(code: "DIR_FAILED", message: "Failed to create directory: \(error.localizedDescription)", details: nil))
            return
        }

        // Recording settings for AAC (M4A)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            print("AudioRecorderPlugin: Creating recorder for path: \(path)")
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true

            print("AudioRecorderPlugin: Preparing to record...")
            let prepared = audioRecorder?.prepareToRecord() ?? false
            print("AudioRecorderPlugin: prepareToRecord result: \(prepared)")

            print("AudioRecorderPlugin: Starting recording...")
            let success = audioRecorder?.record() ?? false
            print("AudioRecorderPlugin: record() result: \(success)")

            if success {
                print("AudioRecorderPlugin: Recording started successfully, isRecording: \(audioRecorder?.isRecording ?? false)")
                result(true)
            } else {
                // Try to get more info about why it failed
                print("AudioRecorderPlugin: record() returned false")
                print("AudioRecorderPlugin: audioRecorder is nil: \(audioRecorder == nil)")
                print("AudioRecorderPlugin: url is valid: \(FileManager.default.isWritableFile(atPath: directory.path))")
                result(FlutterError(code: "RECORD_FAILED", message: "Failed to start recording - record() returned false. Directory writable: \(FileManager.default.isWritableFile(atPath: directory.path))", details: nil))
            }
        } catch {
            print("AudioRecorderPlugin: Exception during recording setup: \(error.localizedDescription)")
            result(FlutterError(code: "INIT_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func stopRecording(result: @escaping FlutterResult) {
        guard let recorder = audioRecorder else {
            result(FlutterError(code: "NO_RECORDER", message: "No active recording", details: nil))
            return
        }

        let wasRecording = recorder.isRecording
        let path = currentFilePath

        recorder.stop()
        audioRecorder = nil

        if wasRecording, let filePath = path {
            // Verify file exists
            if FileManager.default.fileExists(atPath: filePath) {
                result(filePath)
            } else {
                result(FlutterError(code: "FILE_NOT_FOUND", message: "Recording file not created", details: nil))
            }
        } else {
            result(path)
        }

        currentFilePath = nil
    }

    // AVAudioRecorderDelegate
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Recording finished
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Audio recorder encode error: \(error.localizedDescription)")
        }
    }
}
