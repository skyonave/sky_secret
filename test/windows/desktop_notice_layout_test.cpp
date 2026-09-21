#include "../../windows/runner/desktop_notice_layout.h"
#include <cstdio>

bool Equal(RECT left, RECT right) {
  return left.left == right.left && left.top == right.top && left.right == right.right && left.bottom == right.bottom;
}

int main() {
  const SIZE notice{400, 100};
  if (!Equal(DesktopNoticeBounds({0, 0, 1920, 1040}, notice, 12), {760, 928, 1160, 1028})) return 1;
  if (!Equal(DesktopNoticeBounds({-1920, 0, 0, 1040}, notice, 12), {-1160, 928, -760, 1028})) return 2;
  if (!Equal(DesktopNoticeBounds({1920, -1080, 3840, -40}, notice, 12), {2680, -152, 3080, -52})) return 3;
  if (!Equal(DesktopNoticeBounds({0, 0, 2880, 1560}, {600, 150}, 18), {1140, 1392, 1740, 1542})) return 4;
  if (!Equal(DesktopNoticeBounds({0, 0, 320, 90}, notice, 12), {0, 0, 320, 90})) return 5;
  if (!Equal(DesktopNoticeBounds({0, 0, 1080, 1880}, notice, 12), {340, 1768, 740, 1868})) return 6;
  if (!Equal(DesktopNoticeBounds({0, 0, 1921, 1041}, notice, 12), {760, 929, 1160, 1029})) return 7;
  if (!Equal(DesktopNoticeBounds({-1600, -900, 0, -40}, notice, 12), {-1000, -152, -600, -52})) return 8;
  if (!Equal(DesktopNoticeBounds({0, 0, 3840, 2080}, {800, 200}, 24), {1520, 1856, 2320, 2056})) return 9;
  if (!Equal(DesktopNoticeBounds({48, 0, 1920, 1080}, notice, 12), {784, 968, 1184, 1068})) return 10;
  if (!Equal(DesktopNoticeBounds({0, 48, 1920, 1080}, notice, 12), {760, 968, 1160, 1068})) return 11;
  std::puts("11 bottom-center notification placement checks passed");
  return 0;
}
