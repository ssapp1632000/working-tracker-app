#include "audio_recorder_plugin.h"

#include <iostream>
#include <shlobj.h>
#include <codecvt>
#include <locale>

// Helper to convert std::string to std::wstring
static std::wstring StringToWString(const std::string& str) {
    if (str.empty()) return std::wstring();
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

void AudioRecorderPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<AudioRecorderPlugin>(registrar);
    registrar->AddPlugin(std::move(plugin));
}

AudioRecorderPlugin::AudioRecorderPlugin(flutter::PluginRegistrarWindows* registrar) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(),
        "com.silverstone.audio_recorder",
        &flutter::StandardMethodCodec::GetInstance());

    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            HandleMethodCall(call, std::move(result));
        });

    // Initialize Media Foundation
    HRESULT hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to initialize Media Foundation" << std::endl;
    }
}

AudioRecorderPlugin::~AudioRecorderPlugin() {
    if (is_recording_) {
        stop_requested_ = true;
        if (recording_thread_.joinable()) {
            recording_thread_.join();
        }
    }
    MFShutdown();
}

void AudioRecorderPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

    const std::string& method = method_call.method_name();

    if (method == "hasPermission") {
        bool has_permission = HasPermission();
        result->Success(flutter::EncodableValue(has_permission));
    }
    else if (method == "startRecording") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("path"));
            if (it != args->end()) {
                const auto* path = std::get_if<std::string>(&it->second);
                if (path) {
                    bool success = StartRecording(*path);
                    result->Success(flutter::EncodableValue(success));
                    return;
                }
            }
        }
        result->Error("INVALID_ARGS", "Path is required");
    }
    else if (method == "stopRecording") {
        std::string path = StopRecording();
        if (!path.empty()) {
            result->Success(flutter::EncodableValue(path));
        } else {
            result->Error("NO_RECORDER", "No active recording");
        }
    }
    else if (method == "isRecording") {
        result->Success(flutter::EncodableValue(IsRecording()));
    }
    else {
        result->NotImplemented();
    }
}

bool AudioRecorderPlugin::HasPermission() {
    // On Windows, microphone access is typically always available
    // unless blocked by privacy settings. For now, we assume permission is granted.
    // A more robust implementation would check Windows privacy settings.
    return true;
}

bool AudioRecorderPlugin::StartRecording(const std::string& path) {
    if (is_recording_) {
        std::cerr << "AudioRecorderPlugin: Already recording" << std::endl;
        return false;
    }

    current_file_path_ = path;
    stop_requested_ = false;
    is_recording_ = true;

    // Start recording in a background thread
    recording_thread_ = std::thread(&AudioRecorderPlugin::RecordingThread, this);

    std::cout << "AudioRecorderPlugin: Recording started to " << path << std::endl;
    return true;
}

std::string AudioRecorderPlugin::StopRecording() {
    if (!is_recording_) {
        return "";
    }

    stop_requested_ = true;

    if (recording_thread_.joinable()) {
        recording_thread_.join();
    }

    is_recording_ = false;
    std::string path = current_file_path_;
    current_file_path_.clear();

    std::cout << "AudioRecorderPlugin: Recording stopped, file: " << path << std::endl;
    return path;
}

bool AudioRecorderPlugin::IsRecording() {
    return is_recording_;
}

void AudioRecorderPlugin::RecordingThread() {
    HRESULT hr = S_OK;
    IMFMediaSource* pSource = nullptr;
    IMFAttributes* pAttributes = nullptr;
    IMFActivate** ppDevices = nullptr;
    UINT32 deviceCount = 0;

    // Create attributes for audio capture device enumeration
    hr = MFCreateAttributes(&pAttributes, 1);
    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to create attributes" << std::endl;
        is_recording_ = false;
        return;
    }

    // Request audio capture devices
    hr = pAttributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                               MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_AUDCAP_GUID);
    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to set device type" << std::endl;
        pAttributes->Release();
        is_recording_ = false;
        return;
    }

    // Enumerate audio capture devices
    hr = MFEnumDeviceSources(pAttributes, &ppDevices, &deviceCount);
    pAttributes->Release();

    if (FAILED(hr) || deviceCount == 0) {
        std::cerr << "AudioRecorderPlugin: No audio capture devices found" << std::endl;
        is_recording_ = false;
        return;
    }

    // Activate the first audio device
    hr = ppDevices[0]->ActivateObject(IID_PPV_ARGS(&pSource));

    // Release device list
    for (UINT32 i = 0; i < deviceCount; i++) {
        ppDevices[i]->Release();
    }
    CoTaskMemFree(ppDevices);

    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to activate audio device" << std::endl;
        is_recording_ = false;
        return;
    }

    // Create source reader
    hr = MFCreateSourceReaderFromMediaSource(pSource, nullptr, &source_reader_);
    pSource->Release();

    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to create source reader" << std::endl;
        is_recording_ = false;
        return;
    }

    // Configure the source reader to decode to PCM
    IMFMediaType* pAudioType = nullptr;
    hr = MFCreateMediaType(&pAudioType);
    if (SUCCEEDED(hr)) {
        hr = pAudioType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    }
    if (SUCCEEDED(hr)) {
        hr = pAudioType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    }
    if (SUCCEEDED(hr)) {
        hr = source_reader_->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                                                  nullptr, pAudioType);
    }
    if (pAudioType) {
        pAudioType->Release();
    }

    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to configure audio format" << std::endl;
        source_reader_->Release();
        source_reader_ = nullptr;
        is_recording_ = false;
        return;
    }

    // Get the actual format
    IMFMediaType* pActualType = nullptr;
    hr = source_reader_->GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, &pActualType);
    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to get media type" << std::endl;
        source_reader_->Release();
        source_reader_ = nullptr;
        is_recording_ = false;
        return;
    }

    // Create sink writer for AAC output
    std::wstring wpath = StringToWString(current_file_path_);

    IMFAttributes* pSinkAttributes = nullptr;
    MFCreateAttributes(&pSinkAttributes, 1);
    if (pSinkAttributes) {
        pSinkAttributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    }

    hr = MFCreateSinkWriterFromURL(wpath.c_str(), nullptr, pSinkAttributes, &sink_writer_);
    if (pSinkAttributes) {
        pSinkAttributes->Release();
    }

    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to create sink writer: " << std::hex << hr << std::endl;
        pActualType->Release();
        source_reader_->Release();
        source_reader_ = nullptr;
        is_recording_ = false;
        return;
    }

    // Create AAC output type
    IMFMediaType* pOutputType = nullptr;
    hr = MFCreateMediaType(&pOutputType);
    if (SUCCEEDED(hr)) {
        hr = pOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    }
    if (SUCCEEDED(hr)) {
        hr = pOutputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    }
    if (SUCCEEDED(hr)) {
        hr = pOutputType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    }
    if (SUCCEEDED(hr)) {
        hr = pOutputType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 44100);
    }
    if (SUCCEEDED(hr)) {
        hr = pOutputType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
    }
    if (SUCCEEDED(hr)) {
        hr = pOutputType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 16000);
    }

    DWORD streamIndex = 0;
    if (SUCCEEDED(hr)) {
        hr = sink_writer_->AddStream(pOutputType, &streamIndex);
    }
    if (pOutputType) {
        pOutputType->Release();
    }

    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to add output stream: " << std::hex << hr << std::endl;
        pActualType->Release();
        sink_writer_->Release();
        sink_writer_ = nullptr;
        source_reader_->Release();
        source_reader_ = nullptr;
        is_recording_ = false;
        return;
    }

    // Set input type on sink writer
    hr = sink_writer_->SetInputMediaType(streamIndex, pActualType, nullptr);
    pActualType->Release();

    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to set input media type: " << std::hex << hr << std::endl;
        sink_writer_->Release();
        sink_writer_ = nullptr;
        source_reader_->Release();
        source_reader_ = nullptr;
        is_recording_ = false;
        return;
    }

    // Begin writing
    hr = sink_writer_->BeginWriting();
    if (FAILED(hr)) {
        std::cerr << "AudioRecorderPlugin: Failed to begin writing: " << std::hex << hr << std::endl;
        sink_writer_->Release();
        sink_writer_ = nullptr;
        source_reader_->Release();
        source_reader_ = nullptr;
        is_recording_ = false;
        return;
    }

    std::cout << "AudioRecorderPlugin: Recording loop started" << std::endl;

    // Recording loop
    while (!stop_requested_) {
        DWORD dwFlags = 0;
        LONGLONG llTimestamp = 0;
        IMFSample* pSample = nullptr;

        hr = source_reader_->ReadSample(
            MF_SOURCE_READER_FIRST_AUDIO_STREAM,
            0,
            nullptr,
            &dwFlags,
            &llTimestamp,
            &pSample);

        if (FAILED(hr)) {
            std::cerr << "AudioRecorderPlugin: ReadSample failed" << std::endl;
            break;
        }

        if (dwFlags & MF_SOURCE_READERF_ENDOFSTREAM) {
            std::cout << "AudioRecorderPlugin: End of stream" << std::endl;
            break;
        }

        if (pSample) {
            hr = sink_writer_->WriteSample(streamIndex, pSample);
            pSample->Release();

            if (FAILED(hr)) {
                std::cerr << "AudioRecorderPlugin: WriteSample failed" << std::endl;
                break;
            }
        }
    }

    std::cout << "AudioRecorderPlugin: Recording loop ended" << std::endl;

    // Finalize
    if (sink_writer_) {
        sink_writer_->Finalize();
        sink_writer_->Release();
        sink_writer_ = nullptr;
    }

    if (source_reader_) {
        source_reader_->Release();
        source_reader_ = nullptr;
    }

    std::cout << "AudioRecorderPlugin: Recording thread finished" << std::endl;
}
