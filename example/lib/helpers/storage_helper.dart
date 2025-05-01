import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_sync_kit/offline_sync_kit.dart';

/// A helper class that supports Windows platform
class StorageHelper {
  /// Configures the correct SQLite settings for different platforms
  static Future<void> initializeSqlite() async {
    if (Platform.isWindows || Platform.isLinux) {
      // Initialize SQLite FFI
      sqfliteFfiInit();
      // Set FFI database factory
      databaseFactory = databaseFactoryFfi;
      debugPrint('SQLite FFI initialized for ${Platform.operatingSystem}');
    } else {
      debugPrint('Using default SQLite for ${Platform.operatingSystem}');
    }
  }

  /// Creates a StorageServiceImpl class extended for Windows platform
  static Future<StorageService> createPlatformAwareStorageService() async {
    // Initialize SQLite first
    await initializeSqlite();

    // Return StorageServiceImpl - now it will work on all platforms
    final storageService = StorageServiceImpl();
    await storageService.initialize();

    return storageService;
  }
}
