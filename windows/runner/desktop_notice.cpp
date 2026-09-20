#include "desktop_notice.h"
#include "desktop_notice_layout.h"
#include "desktop_notice_surface.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windowsx.h>

#include <memory>
#include <string>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

std::wstring Text(const Map& args, const char* key) {
  const auto found = args.find(Value(key));
  const auto text = found == args.end() ? nullptr : std::get_if<std::string>(&found->second);
  if (!text || text->empty() || text->size() > 16384) return {};
  const auto size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(),
      static_cast<int>(text->size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(size, 0);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(), static_cast<int>(text->size()), result.data(), size);
  return result;
}

int64_t Integer(const Map& args, const char* key) {
  const auto found = args.find(Value(key));
  if (found == args.end()) return -1;
  if (!std::holds_alternative<int32_t>(found->second) && !std::holds_alternative<int64_t>(found->second)) return -1;
  return found->second.LongValue();
}

class DesktopNoticePlugin : public flutter::Plugin {
 public:
  DesktopNoticePlugin(HWND view, flutter::BinaryMessenger* messenger)
      : view_(view),
        channel_(messenger, "skysecret/desktop_notice", &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "hide") {
        Hide();
        result->Success();
        return;
      }
      if (call.method_name() != "show") {
        result->NotImplemented();
        return;
      }
      const auto args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      if (!args) {
        result->Error("arguments", "Invalid notification");
        return;
      }
      title_ = Text(*args, "title");
      message_ = Text(*args, "message");
      const auto dismiss = Text(*args, "dismiss");
      id_ = Integer(*args, "id");
      kind_ = Integer(*args, "kind");
      if (title_.empty() || message_.empty() || dismiss.empty() || id_ < 0 || kind_ < 0 || kind_ > 3) {
        Hide();
        result->Error("arguments", "Invalid notification");
        return;
      }
      if (!Create()) {
        result->Error("window", "Notification window unavailable");
        return;
      }
      SetWindowTextW(window_, (title_ + L". " + message_).c_str());
      SetWindowTextW(close_, dismiss.c_str());
      scroll_ = 0;
      hovered_ = false;
      shown_ = true;
      if (!Follow(true)) {
        Hide();
        result->Error("position", "Notification position unavailable");
        return;
      }
      SetTimer(window_, 1, 100, nullptr);
      InvalidateRect(window_, nullptr, FALSE);
      result->Success();
    });
  }

  ~DesktopNoticePlugin() override {
    shown_ = false;
    if (window_) {
      KillTimer(window_, 1);
      SetWindowLongPtrW(window_, GWLP_USERDATA, 0);
      DestroyWindow(window_);
    }
    if (title_font_) DeleteObject(title_font_);
    if (body_font_) DeleteObject(body_font_);
  }

 private:
  void ReportHover(bool hovered, bool force) {
    if (force || hovered_ != hovered) {
      hovered_ = hovered;
      channel_.InvokeMethod("hover", std::make_unique<Value>(Map{
          {Value("id"), Value(id_)}, {Value("hovered"), Value(hovered)}}));
    }
  }

  int Scale(int value) const { return MulDiv(value, dpi_, 96); }

  COLORREF Accent() const {
    if (kind_ == 3) return RGB(255, 143, 143);
    if (kind_ == 2) return RGB(255, 203, 138);
    if (kind_ == 0) return RGB(117, 217, 160);
    return RGB(121, 201, 235);
  }

  bool Create() {
    if (window_) return true;
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW type{};
    type.lpfnWndProc = WindowProc;
    type.hInstance = instance;
    type.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    type.lpszClassName = L"SkySecretDesktopNotice";
    RegisterClassW(&type);
    window_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        type.lpszClassName, L"", WS_POPUP | WS_CLIPCHILDREN, 0, 0, 0, 0,
        nullptr, nullptr, instance, this);
    if (!window_) return false;
    close_ = CreateWindowExW(0, L"BUTTON", L"", WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,
        0, 0, 0, 0, window_, reinterpret_cast<HMENU>(1), instance, nullptr);
    if (!close_) {
      DestroyWindow(window_);
      window_ = nullptr;
      return false;
    }
    return true;
  }

  void Hide() {
    shown_ = false;
    hovered_ = false;
    if (window_) {
      KillTimer(window_, 1);
      ShowWindow(window_, SW_HIDE);
      SetWindowTextW(window_, L"");
    }
    title_.clear();
    message_.clear();
  }

  void Dismiss() {
    const auto id = id_;
    Hide();
    channel_.InvokeMethod("dismiss", std::make_unique<Value>(Map{{Value("id"), Value(id)}}));
  }

  bool Follow(bool report_hover = false) {
    const auto host = GetAncestor(view_, GA_ROOT);
    MONITORINFO monitor{sizeof(MONITORINFO)};
    if (!IsWindow(host) ||
        !GetMonitorInfoW(MonitorFromWindow(host, MONITOR_DEFAULTTONEAREST), &monitor)) return false;
    const auto dpi = GetDpiForWindow(host);
    if (!body_font_ || dpi_ != dpi) {
      dpi_ = dpi ? dpi : 96;
      if (title_font_) DeleteObject(title_font_);
      if (body_font_) DeleteObject(body_font_);
      title_font_ = CreateFontW(-Scale(13), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
      body_font_ = CreateFontW(-Scale(13), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET,
          OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    }
    const auto width = std::min<LONG>(Scale(400), monitor.rcWork.right - monitor.rcWork.left);
    const auto dc = GetDC(window_);
    const auto old = SelectObject(dc, body_font_);
    RECT text{0, 0, width - Scale(32), 0};
    DrawTextW(dc, message_.c_str(), static_cast<int>(message_.size()), &text, DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
    SelectObject(dc, old);
    ReleaseDC(window_, dc);
    text_height_ = text.bottom;
    const auto height = std::min<LONG>(text_height_ + Scale(58),
        std::min<LONG>(Scale(260), monitor.rcWork.bottom - monitor.rcWork.top));
    const auto rect = DesktopNoticeBounds(monitor.rcWork, {width, height});
    RECT previous{};
    GetWindowRect(window_, &previous);
    if (!EqualRect(&previous, &rect)) {
      SetWindowPos(window_, HWND_TOPMOST, rect.left, rect.top, width, height, SWP_NOACTIVATE);
      SetWindowPos(close_, nullptr, width - Scale(40), Scale(8), Scale(28), Scale(28), SWP_NOZORDER | SWP_NOACTIVATE);
      auto region = DesktopNoticeShape(width, height, dpi_);
      if (region && !SetWindowRgn(window_, region, FALSE)) DeleteObject(region);
      InvalidateRect(window_, nullptr, FALSE);
    }
    DWORD affinity = WDA_EXCLUDEFROMCAPTURE;
    GetWindowDisplayAffinity(host, &affinity);
    SetWindowDisplayAffinity(window_, affinity);
    if (!IsWindowVisible(window_)) ShowWindow(window_, SW_SHOWNOACTIVATE);
    POINT cursor{};
    GetCursorPos(&cursor);
    const bool hovered = GetAncestor(WindowFromPoint(cursor), GA_ROOT) == window_;
    ReportHover(hovered, report_hover);
    return true;
  }

  void Paint() {
    PAINTSTRUCT paint{};
    const auto dc = BeginPaint(window_, &paint);
    RECT bounds{};
    GetClientRect(window_, &bounds);
    PaintDesktopNoticeSurface(dc, bounds, dpi_, RGB(24, 31, 41), Accent());
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, Accent());
    const auto old = SelectObject(dc, title_font_);
    RECT icon{Scale(12), Scale(10), Scale(30), Scale(34)};
    DrawTextW(dc, kind_ == 0 ? L"\x2713" : kind_ == 1 ? L"i" : L"!", 1, &icon,
        DT_CENTER | DT_SINGLELINE | DT_VCENTER | DT_NOPREFIX);
    RECT title{Scale(36), Scale(10), bounds.right - Scale(46), Scale(34)};
    DrawTextW(dc, title_.c_str(), static_cast<int>(title_.size()), &title,
        DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
    SelectObject(dc, body_font_);
    SetTextColor(dc, RGB(228, 244, 250));
    const auto saved = SaveDC(dc);
    IntersectClipRect(dc, Scale(12), Scale(42), bounds.right - Scale(12), bounds.bottom - Scale(12));
    RECT body{Scale(12), Scale(42) - scroll_, bounds.right - Scale(20), Scale(42) + text_height_ - scroll_};
    DrawTextW(dc, message_.c_str(), static_cast<int>(message_.size()), &body, DT_WORDBREAK | DT_NOPREFIX);
    RestoreDC(dc, saved);
    if (text_height_ > bounds.bottom - Scale(54)) {
      const auto track = CreateSolidBrush(RGB(80, 96, 116));
      const auto available = bounds.bottom - Scale(54);
      const auto thumb = std::max<LONG>(Scale(16), available * available / text_height_);
      const auto offset = scroll_ * (available - thumb) / std::max(1L, text_height_ - available);
      RECT bar{bounds.right - Scale(7), Scale(42) + offset, bounds.right - Scale(4), Scale(42) + offset + thumb};
      FillRect(dc, &bar, track);
      DeleteObject(track);
    }
    SelectObject(dc, old);
    EndPaint(window_, &paint);
  }

  void PaintClose(const DRAWITEMSTRUCT& item) {
    const auto brush = CreateSolidBrush((item.itemState & ODS_SELECTED) ? RGB(48, 61, 76) : RGB(33, 43, 56));
    FillRect(item.hDC, &item.rcItem, brush);
    DeleteObject(brush);
    const auto pen = CreatePen(PS_SOLID, std::max(1, Scale(1)), RGB(154, 168, 184));
    const auto old = SelectObject(item.hDC, pen);
    MoveToEx(item.hDC, Scale(10), Scale(10), nullptr);
    LineTo(item.hDC, Scale(18), Scale(18));
    MoveToEx(item.hDC, Scale(18), Scale(10), nullptr);
    LineTo(item.hDC, Scale(10), Scale(18));
    SelectObject(item.hDC, old);
    DeleteObject(pen);
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    auto* self = reinterpret_cast<DesktopNoticePlugin*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<DesktopNoticePlugin*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
      self->window_ = window;
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (message == WM_ERASEBKGND) return 1;
    if (self) {
      if (message == WM_PAINT) { self->Paint(); return 0; }
      if (message == WM_DRAWITEM) { self->PaintClose(*reinterpret_cast<DRAWITEMSTRUCT*>(lparam)); return TRUE; }
      if (message == WM_COMMAND && LOWORD(wparam) == 1 && HIWORD(wparam) == BN_CLICKED) {
        self->Dismiss(); return 0;
      }
      if (message == WM_CLOSE) { self->Dismiss(); return 0; }
      if (message == WM_TIMER && self->shown_) {
        if (!self->Follow()) self->Dismiss();
        return 0;
      }
      if (message == WM_MOUSEWHEEL) {
        RECT bounds{};
        GetClientRect(window, &bounds);
        self->scroll_ = std::clamp<LONG>(self->scroll_ - GET_WHEEL_DELTA_WPARAM(wparam) * self->Scale(36) / WHEEL_DELTA,
            0, std::max(0L, self->text_height_ - (bounds.bottom - self->Scale(54))));
        InvalidateRect(window, nullptr, FALSE);
        return 0;
      }
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  HWND view_;
  HWND window_ = nullptr;
  HWND close_ = nullptr;
  flutter::MethodChannel<Value> channel_;
  HFONT title_font_ = nullptr;
  HFONT body_font_ = nullptr;
  UINT dpi_ = 96;
  std::wstring title_;
  std::wstring message_;
  int64_t id_ = 0;
  int64_t kind_ = 0;
  LONG text_height_ = 0;
  LONG scroll_ = 0;
  bool shown_ = false;
  bool hovered_ = false;
};
}

void RegisterDesktopNotice(FlutterDesktopPluginRegistrarRef core_registrar) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(core_registrar);
  registrar->AddPlugin(std::make_unique<DesktopNoticePlugin>(registrar->GetView()->GetNativeWindow(), registrar->messenger()));
}
