#include <windows.h>
#include <flutter/dart_project.h>
#include <cstdio>
#include <functional>
#include <string>

#include "flutter_window.h"
#include "startup_indicator.h"

HWND StartupWindow() {
  HWND found = nullptr;
  EnumWindows([](HWND window, LPARAM data) -> BOOL {
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    wchar_t name[64]{};
    GetClassNameW(window, name, 64);
    if (process == GetCurrentProcessId() && wcscmp(name, L"SkySecret.Startup") == 0) {
      *reinterpret_cast<HWND*>(data) = window;
      return FALSE;
    }
    return TRUE;
  }, reinterpret_cast<LPARAM>(&found));
  return found;
}

bool WaitFor(const std::function<bool()>& condition, ULONGLONG timeout = 5000) {
  const auto started = GetTickCount64();
  while (!condition()) {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
    if (GetTickCount64() - started >= timeout) return false;
    Sleep(10);
  }
  return true;
}

bool GreenCheck(HWND window) {
  const auto dc = GetDC(window);
  if (!dc) return false;
  const int dpi = GetDpiForWindow(window);
  const auto color = GetPixel(dc, MulDiv(25, dpi, 96), MulDiv(37, dpi, 96));
  ReleaseDC(window, dc);
  return color != CLR_INVALID && GetGValue(color) > 160 && GetRValue(color) < 140;
}

int main() {
  wchar_t enabled[8]{};
  if (!GetEnvironmentVariableW(L"SKYSECRET_STARTUP_INTEGRATION", enabled, 8) || wcscmp(enabled, L"1")) return 77;
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const auto foreground = GetForegroundWindow();
  StartupIndicator startup;
  const auto name = L"Local\\SkySecret.Startup.Test." + std::to_wstring(GetCurrentProcessId());
  startup.Labels(L"Loading test", L"Ready test", L"Failed test");
  startup.Start(name.c_str());
  if (!WaitFor([] { return IsWindowVisible(StartupWindow()) != FALSE; })) {
    std::puts("FAIL indicator not visible before Flutter");
    return 1;
  }
  std::puts("PASS loading indicator visible before Flutter");
  flutter::DartProject project(L"data");
  FlutterWindow main_window(project, &startup);
  if (!main_window.Create(L"SkySecret startup integration", {10, 10}, {460, 600})) return 2;
  if (!IsWindowVisible(StartupWindow())) {
    std::puts("FAIL main window creation stopped loading indicator");
    return 3;
  }
  const auto window = StartupWindow();
  RECT bounds{};
  GetWindowRect(window, &bounds);
  MONITORINFO monitor{sizeof(monitor)};
  GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor);
  const auto gap = MulDiv(12, GetDpiForWindow(window), 96);
  if (bounds.right != monitor.rcWork.right - gap || bounds.bottom != monitor.rcWork.bottom - gap) return 4;
  if (IsWindowVisible(main_window.GetHandle())) return 5;
  if (GetForegroundWindow() != foreground) return 6;
  std::puts("PASS main hidden, indicator at bottom-right, foreground unchanged");
  startup.Finish(true);
  if (!WaitFor([window] { return GreenCheck(window); })) return 7;
  const auto ready = GetTickCount64();
  if (!WaitFor([window] { return !IsWindow(window); }, 2000)) return 8;
  if (GetTickCount64() - ready < 850) return 9;
  std::puts("PASS green ready check and one-second auto-close");
  startup.Stop();
  std::puts("SUCCESS");
  return 0;
}
