#include "startup_indicator.h"

#include <algorithm>
#include <cmath>
#include <flutter_windows.h>

StartupIndicator::~StartupIndicator() { Stop(); }

void StartupIndicator::Start(const wchar_t* instance_mutex) {
  const auto existing = OpenMutexW(SYNCHRONIZE, FALSE, instance_mutex);
  if (existing) {
    CloseHandle(existing);
    return;
  }
  thread_ = std::thread([this] { Run(); });
}

void StartupIndicator::Labels(std::wstring loading, std::wstring ready, std::wstring failed) {
  std::lock_guard<std::mutex> lock(mutex_);
  loading_ = std::move(loading);
  ready_ = std::move(ready);
  failed_ = std::move(failed);
}

void StartupIndicator::Finish(bool success) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (status_ == 0) status_ = success ? 1 : 2;
}

void StartupIndicator::Stop() {
  stopping_ = true;
  const auto window = window_.load();
  if (window) PostMessageW(window, WM_CLOSE, 0, 0);
  if (thread_.joinable()) thread_.join();
}

void StartupIndicator::Run() {
  const auto instance = GetModuleHandleW(nullptr);
  WNDCLASSW klass{};
  klass.lpfnWndProc = WindowProc;
  klass.hInstance = instance;
  klass.lpszClassName = L"SkySecret.Startup";
  klass.hCursor = LoadCursor(nullptr, IDC_ARROW);
  if (!RegisterClassW(&klass)) return;
  POINT cursor{};
  GetCursorPos(&cursor);
  const auto monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{sizeof(info)};
  if (!GetMonitorInfoW(monitor, &info)) {
    UnregisterClassW(klass.lpszClassName, instance);
    return;
  }
  const auto dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const int width = MulDiv(264, dpi, 96);
  const int height = MulDiv(64, dpi, 96);
  const int gap = MulDiv(12, dpi, 96);
  const auto window = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
      klass.lpszClassName, L"SkySecret", WS_POPUP,
      std::max(info.rcWork.left, info.rcWork.right - width - gap),
      std::max(info.rcWork.top, info.rcWork.bottom - height - gap),
      width, height, nullptr, nullptr, instance, this);
  window_ = window;
  if (window) {
    const auto radius = MulDiv(16, dpi, 96);
    const auto region = CreateRoundRectRgn(0, 0, width + 1, height + 1, radius, radius);
    if (region && !SetWindowRgn(window, region, FALSE)) DeleteObject(region);
    if (!stopping_) {
      ShowWindow(window, SW_SHOWNOACTIVATE);
      UpdateWindow(window);
      SetTimer(window, 1, 50, nullptr);
      MSG message{};
      while (!stopping_ && GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
    if (IsWindow(window)) DestroyWindow(window);
  }
  window_ = nullptr;
  UnregisterClassW(klass.lpszClassName, instance);
}

void StartupIndicator::Tick(HWND window) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (displayed_status_ == 0 && status_ != 0) {
      displayed_status_ = status_;
      finished_at_ = GetTickCount64();
    }
  }
  const auto duration = displayed_status_ == 1 ? 1000ULL : 4000ULL;
  if (finished_at_ && GetTickCount64() - finished_at_ >= duration) {
    DestroyWindow(window);
    return;
  }
  phase_ = (phase_ + 1) % 24;
  InvalidateRect(window, nullptr, FALSE);
}

void StartupIndicator::Paint(HWND window) {
  PAINTSTRUCT paint{};
  const auto output = BeginPaint(window, &paint);
  RECT bounds{};
  GetClientRect(window, &bounds);
  const auto dc = CreateCompatibleDC(output);
  const auto bitmap = CreateCompatibleBitmap(output, bounds.right, bounds.bottom);
  const auto old_bitmap = SelectObject(dc, bitmap);
  const auto background = CreateSolidBrush(RGB(24, 33, 43));
  FillRect(dc, &bounds, background);
  DeleteObject(background);
  const int dpi = GetDpiForWindow(window);
  const auto scale = [dpi](int value) { return MulDiv(value, dpi, 96); };
  const auto frame = CreatePen(PS_SOLID, scale(1), RGB(47, 64, 78));
  const auto old_pen = SelectObject(dc, frame);
  const auto old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
  RoundRect(dc, 0, 0, bounds.right - 1, bounds.bottom - 1, scale(16), scale(16));
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(frame);
  const auto color = displayed_status_ == 1 ? RGB(97, 212, 145) :
      displayed_status_ == 2 ? RGB(245, 125, 125) : RGB(118, 203, 232);
  const auto pen = CreatePen(PS_SOLID, scale(2), color);
  SelectObject(dc, pen);
  if (displayed_status_ == 1) {
    const POINT points[] = {{scale(19), scale(32)}, {scale(25), scale(38)}, {scale(37), scale(25)}};
    Polyline(dc, points, 3);
  } else if (displayed_status_ == 2) {
    MoveToEx(dc, scale(21), scale(25), nullptr);
    LineTo(dc, scale(35), scale(39));
    MoveToEx(dc, scale(35), scale(25), nullptr);
    LineTo(dc, scale(21), scale(39));
  } else {
    const auto track = CreateSolidBrush(RGB(47, 64, 78));
    RECT progress{scale(12), bounds.bottom - scale(7), bounds.right - scale(12), bounds.bottom - scale(4)};
    FillRect(dc, &progress, track);
    DeleteObject(track);
    const int length = scale(48);
    const int travel = progress.right - progress.left - length;
    progress.left += travel * phase_ / 24;
    progress.right = progress.left + length;
    const auto active = CreateSolidBrush(color);
    FillRect(dc, &progress, active);
    DeleteObject(active);  }
  SelectObject(dc, old_pen);
  DeleteObject(pen);
  std::wstring text;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    text = displayed_status_ == 1 ? ready_ : displayed_status_ == 2 ? failed_ : loading_;
  }
  const auto font = CreateFontW(-scale(14), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  const auto old_font = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(224, 235, 241));
  RECT text_bounds{scale(displayed_status_ == 0 ? 16 : 52), scale(12), bounds.right - scale(16), bounds.bottom - scale(12)};
  DrawTextW(dc, text.c_str(), -1, &text_bounds, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(dc, old_font);
  DeleteObject(font);
  BitBlt(output, 0, 0, bounds.right, bounds.bottom, dc, 0, 0, SRCCOPY);
  SelectObject(dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(dc);
  EndPaint(window, &paint);
}

LRESULT CALLBACK StartupIndicator::WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<StartupIndicator*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<StartupIndicator*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (self) {
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == WM_PAINT) {
      self->Paint(window);
      return 0;
    }
    if (message == WM_TIMER) {
      self->Tick(window);
      return 0;
    }
    if (message == WM_DESTROY) {
      KillTimer(window, 1);
      self->window_ = nullptr;
      PostQuitMessage(0);
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
