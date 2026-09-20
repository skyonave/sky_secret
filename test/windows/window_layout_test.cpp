#include <windows.h>
#include <dwmapi.h>

#include <cstdio>
#include <cstring>
#include <flutter/standard_method_codec.h>

namespace {
const auto manager_handle = reinterpret_cast<HWND>(static_cast<UINT_PTR>(1));
const auto search_handle = reinterpret_cast<HWND>(static_cast<UINT_PTR>(2));
HWND focused_window = manager_handle;
int position_requests = 0;
UINT last_flags = 0;
RECT last_bounds = {};
int quit_requests = 0;
int close_requests = 0;
HWND closed_window = nullptr;
int show_mode = 0;

BOOL WINAPI RecordShow(HWND, int mode) {
  show_mode = mode;
  return TRUE;
}

void WINAPI RecordQuit(int) { ++quit_requests; }
BOOL WINAPI RecordMessage(HWND window, UINT message, WPARAM wparam, LPARAM) {
  if (message == WM_SYSCOMMAND && wparam == SC_CLOSE) {
    ++close_requests;
    closed_window = window;
  }
  return TRUE;
}

BOOL WINAPI RecordPosition(HWND window, HWND, int x, int y, int width, int height, UINT flags) {
  ++position_requests;
  last_flags = flags;
  last_bounds = RECT{x, y, width, height};
  if ((flags & SWP_NOACTIVATE) == 0) focused_window = window;
  return TRUE;
}

BOOL WINAPI WindowBounds(HWND, LPRECT rect) {
  *rect = RECT{10, 10, 650, 470};
  return TRUE;
}

HWND WINAPI ChildWindow(HWND window, UINT) { return window; }
HRESULT WINAPI ExtendFrame(HWND, const MARGINS*) { return S_OK; }
}

#define SetWindowPos RecordPosition
#define GetWindowRect WindowBounds
#define GetWindow ChildWindow
#define DwmExtendFrameIntoClientArea ExtendFrame
#define PostQuitMessage RecordQuit
#define PostMessageW RecordMessage
#define ShowWindowAsync RecordShow
#include SKY_WINDOW_MANAGER_SOURCE
#undef SetWindowPos
#undef GetWindowRect
#undef GetWindow
#undef DwmExtendFrameIntoClientArea
#undef PostQuitMessage
#undef PostMessageW
#undef ShowWindowAsync

int main(int argc, char** argv) {
  WindowManager window;
  window.native_window = search_handle;
#ifdef SKY_INACTIVE_SHOW
  if (argc > 1 && std::strcmp(argv[1], "--inactive") == 0) {
    window.Show(true);
    if (show_mode != SW_SHOWNOACTIVATE || focused_window != manager_handle) return 9;
    std::puts("Inactive show preserves foreground; no windows created");
    return 0;
  }
#endif
  if (argc > 1 && std::strcmp(argv[1], "--close") == 0) {
    window.Destroy();
    if (quit_requests != 1 || close_requests != 0) return 6;
    quit_requests = 0;
    window.SetPreventClose({{flutter::EncodableValue("isPreventClose"), flutter::EncodableValue(false)}});
    window.Close();
    if (quit_requests != 0 || close_requests != 1 || closed_window != search_handle || window.IsPreventClose()) return 7;
    std::puts("Close targets only the companion HWND; Destroy quits the message loop; no windows created");
    return 0;
  }
  if (argc > 1 && std::strcmp(argv[1], "--topmost") == 0) {
    window.SetAlwaysOnTop({{flutter::EncodableValue("isAlwaysOnTop"), flutter::EncodableValue(true)}});
    if (position_requests != 1) return 8;
  } else if (argc > 1 && std::strcmp(argv[1], "--frame") == 0) {
    window.SetTitleBarStyle({{flutter::EncodableValue("titleBarStyle"), flutter::EncodableValue("hidden")}});
    window.ForceRefresh();
    window.ForceChildRefresh();
    window.SetAsFrameless();
    if (position_requests != 6 || (last_flags & SWP_FRAMECHANGED) == 0) return 3;
  } else {
    window.SetBounds({
        {flutter::EncodableValue("devicePixelRatio"), flutter::EncodableValue(1.5)},
        {flutter::EncodableValue("width"), flutter::EncodableValue(640.0)},
        {flutter::EncodableValue("height"), flutter::EncodableValue(460.0)},
    });
    if (position_requests != 1 || (last_flags & SWP_NOMOVE) == 0 ||
        last_bounds.right != 960 || last_bounds.bottom != 690) return 4;
    if (focused_window != manager_handle) {
      std::fputs("Search preparation stole manager focus while resizing\n", stderr);
      return 1;
    }
    window.SetBounds({
        {flutter::EncodableValue("devicePixelRatio"), flutter::EncodableValue(1.0)},
        {flutter::EncodableValue("x"), flutter::EncodableValue(320.0)},
        {flutter::EncodableValue("y"), flutter::EncodableValue(240.0)},
    });
    if (position_requests != 2 || (last_flags & SWP_NOSIZE) == 0 ||
        last_bounds.left != 320 || last_bounds.top != 240) return 5;
  }
  if (focused_window != manager_handle) {
    std::fputs("Window preparation stole manager focus\n", stderr);
    return 1;
  }
  std::puts("Layout preserves focus and geometry; no windows created");
  return 0;
}
