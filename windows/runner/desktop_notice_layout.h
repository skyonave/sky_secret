#ifndef RUNNER_DESKTOP_NOTICE_LAYOUT_H_
#define RUNNER_DESKTOP_NOTICE_LAYOUT_H_

#include <windows.h>
#include <algorithm>

inline RECT DesktopNoticeBounds(RECT work, SIZE size) {
  const auto width = std::min(size.cx, work.right - work.left);
  const auto height = std::min(size.cy, work.bottom - work.top);
  const auto x = work.left + (work.right - work.left - width) / 2;
  const auto y = work.top + (work.bottom - work.top - height) / 2;
  return {x, y, x + width, y + height};
}

#endif
