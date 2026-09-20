import 'dart:ui';

abstract final class TotpWindowLayout {
  static const tileHeight = 56.0;

  static const tileWidth = 230.0;

  static const tileGap = 0.0;

  static const headerHeight = 32.0;

  static const tileRadius = 6.0;

  static const windowGap = 12.0;

  static int visibleSlots(double height) {
    final slots = ((height - TotpWindowLayout.headerHeight) / TotpWindowLayout.tileHeight).floor();
    return slots < 0 ? 0 : slots;
  }

  static List<Rect> tileRects(Size size) => [
    for (var index = 0; index < TotpWindowLayout.visibleSlots(size.height); index++)
      Rect.fromLTWH(
        0,
        TotpWindowLayout.headerHeight + index * TotpWindowLayout.tileHeight,
        size.width,
        TotpWindowLayout.tileHeight,
      ),
  ];

  static Size windowSize(Rect main, Rect work, {int count = 1}) {
    final bottom = main.bottom.clamp(work.top, work.bottom).toDouble();
    final available = TotpWindowLayout.visibleSlots(bottom - work.top);
    final capacity = available < 1 ? 1 : available;
    final slots = count.clamp(1, capacity);
    return Size(TotpWindowLayout.tileWidth, TotpWindowLayout.headerHeight + slots * TotpWindowLayout.tileHeight);
  }
}
