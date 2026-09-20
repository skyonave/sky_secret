#include "../../windows/runner/desktop_notice_layout.h"
#include <cstdio>

bool Equal(RECT left, RECT right) {
  return left.left == right.left && left.top == right.top && left.right == right.right && left.bottom == right.bottom;
}

int main() {
  const SIZE notice{400, 100};
  if (!Equal(DesktopNoticeBounds({0, 0, 1920, 1040}, notice), {760, 470, 1160, 570})) return 1;
  if (!Equal(DesktopNoticeBounds({-1920, 0, 0, 1040}, notice), {-1160, 470, -760, 570})) return 2;
  if (!Equal(DesktopNoticeBounds({1920, -1080, 3840, -40}, notice), {2680, -610, 3080, -510})) return 3;
  if (!Equal(DesktopNoticeBounds({80, 0, 1920, 1080}, notice), {800, 490, 1200, 590})) return 4;
  if (!Equal(DesktopNoticeBounds({0, 40, 1920, 1080}, notice), {760, 510, 1160, 610})) return 5;
  if (!Equal(DesktopNoticeBounds({0, 0, 2880, 1560}, {600, 150}), {1140, 705, 1740, 855})) return 6;
  if (!Equal(DesktopNoticeBounds({0, 0, 320, 90}, notice), {0, 0, 320, 90})) return 7;
  if (!Equal(DesktopNoticeBounds({0, 0, 1080, 1880}, notice), {340, 890, 740, 990})) return 8;
  if (!Equal(DesktopNoticeBounds({0, 0, 1921, 1040}, notice), {760, 470, 1160, 570})) return 9;
  std::puts("9 screen-center notification placement checks passed");
  return 0;
}
