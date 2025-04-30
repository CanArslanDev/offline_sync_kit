import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:offline_sync_kit/offline_sync_kit.dart';

/// Windows platformunu da destekleyen bir yardımcı sınıf
class StorageHelper {
  /// Platformlara göre doğru SQLite ayarlarını yapar
  static Future<void> initializeSqlite() async {
    if (Platform.isWindows || Platform.isLinux) {
      // FFI SQLite'ı başlat
      sqfliteFfiInit();
      // FFI veritabanı factory'sini ayarla
      databaseFactory = databaseFactoryFfi;
      debugPrint('SQLite FFI initialized for ${Platform.operatingSystem}');
    } else {
      debugPrint('Using default SQLite for ${Platform.operatingSystem}');
    }
  }

  /// Windows platformu için StorageServiceImpl sınıfını genişleten bir sınıf oluştur
  static Future<StorageService> createPlatformAwareStorageService() async {
    // Önce SQLite'ı başlat
    await initializeSqlite();

    // StorageServiceImpl'i döndür - artık tüm platformlarda çalışacak
    final storageService = StorageServiceImpl();
    await storageService.initialize();

    return storageService;
  }
}
