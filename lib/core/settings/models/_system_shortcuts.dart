part of '../repositories/shortcut_settings.dart';

abstract final class SystemShortcuts {
  static HotKey defaultManager() => HotKey(
    key: PhysicalKeyboardKey.space,
    modifiers: [HotKeyModifier.shift],
    scope: HotKeyScope.system,
  );

  static HotKey defaultSearch() => HotKey(key: PhysicalKeyboardKey.keyF, modifiers: [], scope: HotKeyScope.system);

  static const supportedModifiers = [
    HotKeyModifier.control,
    HotKeyModifier.alt,
    HotKeyModifier.shift,
    HotKeyModifier.meta,
  ];

  static bool isValid(HotKey key) {
    try {
      return key.scope == HotKeyScope.system &&
          key.physicalKey.keyCode != null &&
          !HotKeyModifier.values.any(
            (m) => m.physicalKeys.contains(key.physicalKey),
          ) &&
          (key.modifiers ?? []).every(SystemShortcuts.supportedModifiers.contains);
    } catch (_) {
      return false;
    }
  }

  static bool same(HotKey a, HotKey b) =>
      a.physicalKey == b.physicalKey &&
      SystemShortcuts.supportedModifiers.every(
        (m) => (a.modifiers ?? []).contains(m) == (b.modifiers ?? []).contains(m),
      );

  static const modifierLabels = {
    HotKeyModifier.control: 'Ctrl',
    HotKeyModifier.alt: 'Alt',
    HotKeyModifier.shift: 'Shift',
    HotKeyModifier.meta: 'Win',
  };

  static String label(HotKey key) {
    final physical = key.physicalKey;
    final label = physical == PhysicalKeyboardKey.space ? 'Space' : physical.logicalKey?.keyLabel;
    return [
      for (final modifier in SystemShortcuts.supportedModifiers)
        if ((key.modifiers ?? []).contains(modifier)) SystemShortcuts.modifierLabels[modifier]!,
      if (label != null && label.isNotEmpty) label else '0x${physical.usbHidUsage.toRadixString(16)}',
    ].join(' + ');
  }
}
