#include "secret_drag_preview.h"

#include <algorithm>
#include <utility>

SecretDragPreview::SecretDragPreview(HWND owner, std::wstring title) : title_(std::move(title)) {
  const auto instance = GetModuleHandleW(nullptr);
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = L"SkySecretDragPreview";
  window_class.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);
  window_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
      window_class.lpszClassName, L"", WS_POPUP, 0, 0, 0, 0, owner, nullptr, instance, this);
  if (window_) {
    SetLayeredWindowAttributes(window_, 0, 245, LWA_ALPHA);
    DWORD affinity = WDA_EXCLUDEFROMCAPTURE;
    GetWindowDisplayAffinity(owner, &affinity);
    SetWindowDisplayAffinity(window_, affinity);
  }
}

SecretDragPreview::~SecretDragPreview() {
  if (window_) DestroyWindow(window_);
  if (title_font_) DeleteObject(title_font_);
  if (label_font_) DeleteObject(label_font_);
  if (!title_.empty()) SecureZeroMemory(title_.data(), title_.size() * sizeof(wchar_t));
}

void SecretDragPreview::Hide() {
  if (window_) ShowWindow(window_, SW_HIDE);
}

void SecretDragPreview::Update(POINT point, const std::wstring& label, bool ready) {
  if (!window_) return;
  const auto under = WindowFromPoint(point);
  const auto dpi = under ? GetDpiForWindow(under) : 96;
  const auto scale = [dpi](int value) { return MulDiv(value, dpi ? dpi : 96, 96); };
  const int width = scale(224);
  const int height = scale(58);
  const bool changed = dpi_ != dpi || label_ != label || ready_ != ready;
  if (dpi_ != dpi) {
    dpi_ = dpi;
    if (title_font_) DeleteObject(title_font_);
    if (label_font_) DeleteObject(label_font_);
    title_font_ = CreateFontW(-scale(13), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    label_font_ = CreateFontW(-scale(12), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    auto region = CreateRoundRectRgn(0, 0, width + 1, height + 1, scale(14), scale(14));
    if (region && !SetWindowRgn(window_, region, FALSE)) DeleteObject(region);
  }
  label_ = label;
  ready_ = ready;
  MONITORINFO monitor{sizeof(MONITORINFO)};
  GetMonitorInfoW(MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST), &monitor);
  auto x = point.x + scale(18);
  auto y = point.y + scale(22);
  if (x + width > monitor.rcWork.right) x = point.x - width - scale(18);
  if (y + height > monitor.rcWork.bottom) y = point.y - height - scale(18);
  SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE | SWP_SHOWWINDOW);
  if (changed) InvalidateRect(window_, nullptr, FALSE);
}

void SecretDragPreview::Paint() {
  PAINTSTRUCT paint{};
  const auto dc = BeginPaint(window_, &paint);
  RECT bounds{};
  GetClientRect(window_, &bounds);
  const auto buffer = CreateCompatibleDC(dc);
  const auto bitmap = CreateCompatibleBitmap(dc, bounds.right, bounds.bottom);
  const auto old_bitmap = SelectObject(buffer, bitmap);
  const auto background = CreateSolidBrush(RGB(27, 32, 39));
  FillRect(buffer, &bounds, background);
  DeleteObject(background);
  const auto scale = [this](int value) { return MulDiv(value, dpi_ ? dpi_ : 96, 96); };
  const auto accent = ready_ ? RGB(117, 217, 160) : RGB(159, 171, 187);
  const auto dot = CreateSolidBrush(accent);
  const auto old_brush = SelectObject(buffer, dot);
  const auto old_pen = SelectObject(buffer, GetStockObject(NULL_PEN));
  Ellipse(buffer, scale(12), scale(16), scale(18), scale(22));
  SelectObject(buffer, old_pen);
  SelectObject(buffer, old_brush);
  DeleteObject(dot);
  SetBkMode(buffer, TRANSPARENT);
  SetTextColor(buffer, RGB(236, 241, 247));
  const auto old_font = SelectObject(buffer, title_font_);
  RECT title{scale(26), scale(8), bounds.right - scale(12), scale(29)};
  DrawTextW(buffer, title_.c_str(), static_cast<int>(title_.size()), &title,
      DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(buffer, label_font_);
  SetTextColor(buffer, accent);
  RECT label{scale(26), scale(30), bounds.right - scale(12), bounds.bottom - scale(8)};
  DrawTextW(buffer, label_.c_str(), static_cast<int>(label_.size()), &label,
      DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  SelectObject(buffer, old_font);
  BitBlt(dc, 0, 0, bounds.right, bounds.bottom, buffer, 0, 0, SRCCOPY);
  SelectObject(buffer, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(buffer);
  EndPaint(window_, &paint);
}

LRESULT CALLBACK SecretDragPreview::WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* preview = reinterpret_cast<SecretDragPreview*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    preview = static_cast<SecretDragPreview*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    preview->window_ = window;
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(preview));
  }
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_PAINT && preview) {
    preview->Paint();
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
