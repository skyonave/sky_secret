#include <cstdio>
#include <windows.h>

bool activated = false;
BOOL HiddenNoticeShow(HWND window, int command) {
  if (command == SW_HIDE) return ShowWindow(window, command);
  if (command != SW_SHOWNOACTIVATE) activated = true;
  return FALSE;
}

#define ShowWindow HiddenNoticeShow
#include "../../windows/runner/desktop_notice.cpp"
#undef ShowWindow

class ShutdownMessenger : public flutter::BinaryMessenger {
 public:
  bool available = true;
  mutable int invalid_calls = 0;
  int registrations = 0;
  flutter::BinaryMessageHandler incoming;

  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply = nullptr) const override {
    if (!available) ++invalid_calls;
  }

  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler handler) override {
    if (!available) ++invalid_calls;
    if (handler) ++registrations;
    incoming = std::move(handler);
  }
};

bool Above(HWND front, HWND back) {
  for (auto window = GetTopWindow(nullptr); window; window = GetWindow(window, GW_HWNDNEXT)) {
    if (window == front) return true;
    if (window == back) return false;
  }
  return false;
}

bool CheckReassertion() {
  const auto foreground = GetForegroundWindow();
  const auto host = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"STATIC", L"", WS_POPUP,
      10, 10, 460, 600, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  const auto search = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, L"STATIC", L"", WS_POPUP,
      10, 10, 360, 64, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  bool passed = false;
  if (host && search) {
    ShutdownMessenger messenger;
    DesktopNoticePlugin plugin(host, &messenger);
    const auto message = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(flutter::MethodCall<Value>(
        "show", std::make_unique<Value>(Map{
          {Value("title"), Value("Synthetic error")}, {Value("message"), Value("Synthetic message")},
          {Value("dismiss"), Value("Close")}, {Value("id"), Value(1)}, {Value("kind"), Value(3)}})));
    bool success = false;
    messenger.incoming(message->data(), message->size(), [&](const uint8_t* bytes, size_t size) {
      success = size > 0 && bytes[0] == 0;
    });
    HWND notice = nullptr;
    EnumThreadWindows(GetCurrentThreadId(), [](HWND window, LPARAM output) -> BOOL {
      wchar_t name[128]{};
      GetClassNameW(window, name, 128);
      if (wcscmp(name, L"SkySecretDesktopNotice") == 0) *reinterpret_cast<HWND*>(output) = window;
      return TRUE;
    }, reinterpret_cast<LPARAM>(&notice));
    RECT before{}, after{};
    if (notice && success && GetWindowRect(notice, &before)) {
      SetWindowPos(search, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
      const bool covered = Above(search, notice);
      SendMessageW(notice, WM_TIMER, 1, 0);
      GetWindowRect(notice, &after);
      MONITORINFO monitor{sizeof(MONITORINFO)};
      GetMonitorInfoW(MonitorFromWindow(host, MONITOR_DEFAULTTONEAREST), &monitor);
      const auto center = DesktopNoticeBounds(monitor.rcWork, {after.right - after.left, after.bottom - after.top}, MulDiv(12, GetDpiForWindow(host), 96));
      passed = covered && Above(notice, search) && EqualRect(&before, &after) && EqualRect(&center, &after) &&
          !IsWindowVisible(notice) && !activated && foreground == GetForegroundWindow();
    }
  }
  if (search) DestroyWindow(search);
  if (host) DestroyWindow(host);
  return passed;
}

int main() {
  ShutdownMessenger messenger;
  {
    DesktopNoticePlugin notice(nullptr, &messenger);
    if (messenger.registrations != 1) return 2;
    messenger.available = false;
  }
  if (messenger.invalid_calls != 0) {
    std::fputs("Notification destructor accessed messenger after engine invalidation\n", stderr);
    return 1;
  }
  if (!CheckReassertion()) {
    std::fputs("Notification bottom center or unchanged-bounds topmost regression failed\n", stderr);
    return 3;
  }
  std::puts("Notification teardown, bottom center and topmost reassertion passed; test windows stayed hidden");
  return 0;
}
