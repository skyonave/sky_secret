#ifndef RUNNER_DESKTOP_NOTICE_LAYOUT_H_
#define RUNNER_DESKTOP_NOTICE_LAYOUT_H_

#include <windows.h>
#include <algorithm>

inline RECT DesktopNoticeBounds(RECT work, SIZE size, LONG gap) {
  const auto width = std::min(size.cx, work.right - work.left);
  const auto height = std::min(size.cy, work.bottom - work.top);
  const auto bottom_gap = std::clamp(gap, 0L, work.bottom - work.top - height);
  const auto x = work.left + (work.right - work.left - width) / 2;
  const auto y = work.bottom - bottom_gap - height;
  return {x, y, x + width, y + height};
}

#endif
