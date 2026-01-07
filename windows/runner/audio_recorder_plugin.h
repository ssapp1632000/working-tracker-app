#ifndef AUDIO_RECORDER_PLUGIN_H_
#define AUDIO_RECORDER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <mmdeviceapi.h>

#include <string>
#include <memory>
#include <atomic>
#include <thread>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")

class AudioRecorderPlugin {
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    AudioRecorderPlugin(flutter::PluginRegistrarWindows* registrar);
    ~AudioRecorderPlugin();

private:
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    bool HasPermission();
    bool StartRecording(const std::string& path);
    std::string StopRecording();
    bool IsRecording();

    void RecordingThread();

    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    std::string current_file_path_;
    std::atomic<bool> is_recording_{false};
    std::atomic<bool> stop_requested_{false};
    std::thread recording_thread_;

    IMFSourceReader* source_reader_ = nullptr;
    IMFSinkWriter* sink_writer_ = nullptr;
};

#endif  // AUDIO_RECORDER_PLUGIN_H_
