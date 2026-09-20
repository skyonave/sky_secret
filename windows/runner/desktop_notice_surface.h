#ifndef RUNNER_DESKTOP_NOTICE_SURFACE_H_
#define RUNNER_DESKTOP_NOTICE_SURFACE_H_

#include <windows.h>
#include <algorithm>

inline HRGN DesktopNoticeShape(int width, int height, UINT dpi) {
  const auto diameter = std::max(2, MulDiv(12, dpi, 96));
  return CreateRoundRectRgn(0, 0, width, height, diameter, diameter);
}

inline void PaintDesktopNoticeSurface(HDC dc, RECT bounds, UINT dpi, COLORREF background, COLORREF accent) {
  const auto region = DesktopNoticeShape(bounds.right, bounds.bottom, dpi);
  if (!region) return;
  const auto fill = CreateSolidBrush(background);
  FillRgn(dc, region, fill);
  DeleteObject(fill);
  const auto border = CreateSolidBrush(accent);
  const auto thickness = std::max(1, MulDiv(1, dpi, 96));
  FrameRgn(dc, region, border, thickness, thickness);
  DeleteObject(border);
  DeleteObject(region);
}

#endif
