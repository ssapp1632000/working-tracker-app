#include "flutter_window.h"

#include <optional>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "audio_recorder_plugin.h"

// Static pointer for method channel callback
static FlutterWindow* g_flutter_window = nullptr;

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  g_flutter_window = this;
}

FlutterWindow::~FlutterWindow() {
  g_flutter_window = nullptr;
}

void FlutterWindow::SetClickThroughEnabled(bool enabled) {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  if (enabled) {
    // Set flag FIRST before starting timer
    click_through_enabled_ = true;

    // Reset state tracking
    is_transparent_ = false;

    // Start polling mouse position to toggle transparency based on hover
    // Only start timer if click-through is still enabled (prevent race conditions)
    if (mouse_poll_timer_ == 0 && click_through_enabled_) {
      mouse_poll_timer_ = SetTimer(hwnd, 1, 30, MousePollTimerProc);
    }

    // Immediately set transparent state for initial click-through
    // This ensures clicks pass through immediately on mode switch
    LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT);
    is_transparent_ = true;
  } else {
    // Set flag to FALSE FIRST to prevent any timer callbacks from running
    click_through_enabled_ = false;

    // Stop polling - any pending timer callbacks will be blocked by the flag above
    if (mouse_poll_timer_ != 0) {
      KillTimer(hwnd, mouse_poll_timer_);
      mouse_poll_timer_ = 0;
    }

    // ALWAYS remove WS_EX_TRANSPARENT when disabling (don't rely on cached state)
    // This prevents state desync after multiple mode switches
    LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, (exStyle | WS_EX_LAYERED) & ~WS_EX_TRANSPARENT);
    is_transparent_ = false;

    // Force window update to ensure the style change takes effect immediately
    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }
}

void CALLBACK FlutterWindow::MousePollTimerProc(HWND hwnd, UINT uMsg, UINT_PTR idEvent, DWORD dwTime) {
  if (g_flutter_window && g_flutter_window->click_through_enabled_) {
    g_flutter_window->UpdateTransparencyForMousePosition();
  }
}

void FlutterWindow::RestoreNormalWindowStyle() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  // Restore standard window style with resize borders (WS_THICKFRAME)
  // WS_OVERLAPPEDWINDOW = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX
  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  style |= WS_OVERLAPPEDWINDOW;
  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  // Remove layered/transparent extended styles
  LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  exStyle &= ~(WS_EX_LAYERED | WS_EX_TRANSPARENT);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle);

  // Force window to recalculate frame and repaint
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

void FlutterWindow::SetFrameless(bool frameless) {
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);

  if (frameless) {
    // Remove all window frame styles - make completely frameless
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
    // Keep only WS_POPUP for a borderless window
    style |= WS_POPUP;
  } else {
    // Restore window frame styles (but not full WS_OVERLAPPEDWINDOW since we use hidden title bar)
    style &= ~WS_POPUP;
    style |= WS_CAPTION | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, style);

  // Force window to recalculate frame and repaint
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}

void FlutterWindow::UpdateTransparencyForMousePosition() {
  HWND hwnd = GetHandle();
  if (!hwnd || !click_through_enabled_) return;

  // Get mouse position in screen coordinates
  POINT pt;
  GetCursorPos(&pt);

  // Get window rect
  RECT windowRect;
  GetWindowRect(hwnd, &windowRect);

  // Check if mouse is within window bounds
  bool mouseInWindow = (pt.x >= windowRect.left && pt.x < windowRect.right &&
                        pt.y >= windowRect.top && pt.y < windowRect.bottom);

  if (mouseInWindow) {
    // Convert to client coordinates
    POINT clientPt = pt;
    ScreenToClient(hwnd, &clientPt);

    // Get window width
    RECT clientRect;
    GetClientRect(hwnd, &clientRect);
    int windowWidth = clientRect.right - clientRect.left;

    // Visible width when collapsed (85px from right edge)
    const int visibleWidth = 85;
    int clickableLeft = windowWidth - visibleWidth;

    // If mouse is in visible area, make window clickable
    if (clientPt.x >= clickableLeft) {
      if (is_transparent_) {
        LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, (exStyle | WS_EX_LAYERED) & ~WS_EX_TRANSPARENT);
        is_transparent_ = false;
      }
      return;
    }
  }

  // Mouse not in visible area - make transparent
  if (!is_transparent_) {
    LONG_PTR exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT);
    is_transparent_ = true;
  }
}

void FlutterWindow::SetupMethodChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.worktracker/click_through",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setClickThroughEnabled") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled) {
            SetClickThroughEnabled(*enabled);
            result->Success();
            return;
          }
          result->Error("INVALID_ARGS", "Expected boolean argument");
        } else if (call.method_name() == "restoreNormalWindowStyle") {
          RestoreNormalWindowStyle();
          result->Success();
        } else if (call.method_name() == "setFrameless") {
          const auto* frameless = std::get_if<bool>(call.arguments());
          if (frameless) {
            SetFrameless(*frameless);
            result->Success();
            return;
          }
          result->Error("INVALID_ARGS", "Expected boolean argument");
        } else {
          result->NotImplemented();
        }
      });
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Register audio recorder plugin
  AudioRecorderPlugin::RegisterWithRegistrar(
      flutter_controller_->engine()->GetRegistrarForPlugin("AudioRecorderPlugin"));

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Setup method channel for click-through control
  SetupMethodChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Clean up timer
  if (mouse_poll_timer_ != 0) {
    KillTimer(GetHandle(), mouse_poll_timer_);
    mouse_poll_timer_ = 0;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
