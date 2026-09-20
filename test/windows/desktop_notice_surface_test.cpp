#include "../../windows/runner/desktop_notice_surface.h"
#include <cstdio>

bool CheckSurface(UINT dpi) {
  const auto width = MulDiv(400, dpi, 96);
  const auto height = MulDiv(94, dpi, 96);
  const RECT bounds{0, 0, width, height};
  const auto dc = CreateCompatibleDC(nullptr);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels = nullptr;
  const auto bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
  if (!dc || !bitmap) return false;
  const auto previous = SelectObject(dc, bitmap);
  const auto outside = RGB(255, 255, 255);
  const auto background = RGB(24, 31, 41);
  const auto border = RGB(255, 143, 143);
  FillRect(dc, &bounds, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  PaintDesktopNoticeSurface(dc, bounds, dpi, background, border);
  const auto shape = DesktopNoticeShape(width, height, dpi);
  bool valid = GetPixel(dc, width / 2, height / 2) == background;
  int curved_border_pixels = 0;
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const auto color = GetPixel(dc, x, y);
      if (!PtInRegion(shape, x, y)) {
        if (color != outside) valid = false;
        continue;
      }
      const bool boundary = !PtInRegion(shape, x - 1, y) || !PtInRegion(shape, x + 1, y) ||
          !PtInRegion(shape, x, y - 1) || !PtInRegion(shape, x, y + 1);
      if (boundary) {
        if (color != border) valid = false;
        if (x > 1 && x < width - 2 && y > 1 && y < height - 2) ++curved_border_pixels;
      }
    }
  }
  valid = valid && curved_border_pixels > 0 && GetPixel(dc, 0, 0) == outside &&
      GetPixel(dc, width - 1, 0) == outside && GetPixel(dc, 0, height - 1) == outside &&
      GetPixel(dc, width - 1, height - 1) == outside;
  DeleteObject(shape);
  SelectObject(dc, previous);
  DeleteObject(bitmap);
  DeleteDC(dc);
  return valid;
}

int main() {
  for (const UINT dpi : {96u, 120u, 144u, 192u}) {
    if (!CheckSurface(dpi)) {
      std::printf("Notification border failed at %u DPI\n", dpi);
      return 1;
    }
  }
  std::puts("Notification border pixels passed at 100%, 125%, 150%, 200% DPI");
  return 0;
}
