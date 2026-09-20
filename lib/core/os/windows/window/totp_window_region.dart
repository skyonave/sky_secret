import 'dart:ffi' hide Size;
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import '../../../desktop/totp/services/totp_window_layout.dart';

abstract final class WindowRegion {
  static final _gdi = DynamicLibrary.open('gdi32.dll');

  static final _roundRegion = WindowRegion._gdi
      .lookupFunction<
        Pointer<Void> Function(Int32, Int32, Int32, Int32, Int32, Int32),
        Pointer<Void> Function(int, int, int, int, int, int)
      >('CreateRoundRectRgn');

  static void configureTotpFrame(int id) => using((arena) {
    final window = win32.HWND(Pointer.fromAddress(id));
    final border = arena<Uint32>()..value = 0xFFFFFFFE;
    final corners = arena<Int32>()..value = 1;
    win32.DwmSetWindowAttribute(window, win32.DWMWA_BORDER_COLOR, border.cast(), sizeOf<Uint32>());
    win32.DwmSetWindowAttribute(window, win32.DWMWA_WINDOW_CORNER_PREFERENCE, corners.cast(), sizeOf<Int32>());
  });

  static void setTotp(int id, Size size) => WindowRegion.setRounded(id, size, TotpWindowLayout.tileRadius);

  static void setRounded(int id, Size size, double radius) {
    final window = win32.HWND(Pointer.fromAddress(id));
    final dpi = win32.GetDpiForWindow(window);
    if (dpi == 0) throw StateError('Window scale unavailable');
    final scale = dpi / 96;
    final region = WindowRegion._roundRegion(
      0,
      0,
      (size.width * scale).round(),
      (size.height * scale).round(),
      (radius * 2 * scale).round(),
      (radius * 2 * scale).round(),
    );
    if (region.address == 0) throw StateError('Window region unavailable');
    if (win32.SetWindowRgn(window, win32.HRGN(region), true) == 0) {
      win32.DeleteObject(win32.HGDIOBJ(region));
      throw StateError('Window shape unavailable');
    }
  }
}
