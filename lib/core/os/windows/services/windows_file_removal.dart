import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

abstract final class WindowsFileRemoval {
  static bool removeUnchanged({
    required String path,
    required String root,
    required Uint8List expected,
    required bool Function() allowed,
  }) {
    if (!Platform.isWindows || expected.length > 65536 || !allowed()) return false;
    return using((arena) {
      final handle = CreateFile(
        PCWSTR(path.toNativeUtf16(allocator: arena)),
        GENERIC_READ | DELETE,
        FILE_SHARE_READ,
        null,
        OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT,
        null,
      ).value;
      if (!handle.isValid) return false;
      try {
        final information = arena<BY_HANDLE_FILE_INFORMATION>();
        if (!GetFileInformationByHandle(handle, information).value) return false;
        final attributes = information.ref.dwFileAttributes;
        if ((attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0 ||
            information.ref.nFileSizeHigh != 0 ||
            information.ref.nFileSizeLow != expected.length) {
          return false;
        }
        final name = arena<Uint16>(32768).cast<Utf16>();
        final length = GetFinalPathNameByHandle(handle, PWSTR(name), 32768, FILE_NAME_NORMALIZED).value;
        if (length == 0 || length >= 32768) return false;
        final resolved = _normalize(name.toDartString(length: length));
        if (resolved != _normalize(path) || !resolved.startsWith('${_normalize(root)}\\')) return false;
        final buffer = arena<Uint8>(expected.length + 1);
        final bytes = buffer.asTypedList(expected.length + 1);
        try {
          final read = arena<Uint32>();
          if (!ReadFile(handle, buffer, bytes.length, read, null).value || read.value != expected.length) {
            return false;
          }
          for (var index = 0; index < expected.length; index++) {
            if (bytes[index] != expected[index]) return false;
          }
          if (!allowed()) return false;
          final disposition = arena<Uint8>()..value = 1;
          return SetFileInformationByHandle(handle, FileDispositionInfo, disposition, 1).value;
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      } finally {
        CloseHandle(handle);
      }
    });
  }

  static String _normalize(String path) {
    var normalized = path.replaceAll('/', '\\');
    if (normalized.startsWith('\\\\?\\UNC\\')) {
      normalized = '\\\\${normalized.substring(8)}';
    } else if (normalized.startsWith('\\\\?\\')) {
      normalized = normalized.substring(4);
    }
    return normalized.toLowerCase();
  }
}
