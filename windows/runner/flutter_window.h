#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Enable or disable click-through mode using WS_EX_TRANSPARENT
  void SetClickThroughEnabled(bool enabled);

  // Restore normal window style (WS_OVERLAPPEDWINDOW) for proper resize/drag
  void RestoreNormalWindowStyle();

  // Set frameless mode (remove all window frame styles)
  void SetFrameless(bool frameless);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Click-through state
  bool click_through_enabled_ = false;

  // Timer for mouse position polling
  UINT_PTR mouse_poll_timer_ = 0;

  // Track if currently transparent
  bool is_transparent_ = false;

  // Setup method channel
  void SetupMethodChannel();

  // Update transparency based on mouse position
  void UpdateTransparencyForMousePosition();

  // Static timer callback
  static void CALLBACK MousePollTimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
