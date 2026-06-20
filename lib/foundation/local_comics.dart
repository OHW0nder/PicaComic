import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/tools/zip_reader.dart';

/// 本地漫画库的管理器。
class LocalComicsManager {
  LocalComicsManager._create();

  static LocalComicsManager? _instance;

  factory LocalComicsManager() => _instance ??= LocalComicsManager._create();

  final List<LocalComic> _comics = [];

  List<LocalComic> get comics => List.unmodifiable(_comics);

  bool _loaded = false;

  String get _filePath => "${App.dataPath}${pathSep}local_comics.json";

  String get _coverDir => "${App.dataPath}${pathSep}local_covers";

  String get pathSep => Platform.pathSeparator;

  /// 从磁盘加载已导入的漫画列表。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = File(_filePath);
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final list = json['comics'] as List;
        _comics.clear();
        for (final item in list) {
          final comic = LocalComic.fromMap(item as Map<String, dynamic>);
          // 仅保留文件仍然存在的条目
          if (await File(comic.path).exists()) {
            _comics.add(comic);
          }
        }
      }
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "IO",
          "Failed to load local comics\n$e\n$s");
    }
  }

  /// 导入一个 ZIP 文件。返回导入成功的漫画，失败返回 null。
  Future<LocalComic?> import(String filePath) async {
    await load();
    final existing = _comics.where((c) => c.path == filePath);
    if (existing.isNotEmpty) return existing.first;

    final comic = await ZipReader.readComic(filePath);
    if (comic == null) return null;

    // 缓存封面
    await _cacheCover(comic);

    _comics.add(comic);
    await _save();
    return comic;
  }

  /// 提取并缓存封面缩略图。
  Future<void> _cacheCover(LocalComic comic) async {
    try {
      final dir = Directory(_coverDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // 取第一张图作为封面
      final bytes = await ZipReader.readImage(comic.path, 0);
      final hash = sha256.convert(bytes).toString().substring(0, 16);
      final coverFile = File("${_coverDir}${pathSep}$hash.jpg");
      if (!await coverFile.exists()) {
        await coverFile.writeAsBytes(bytes);
      }
      comic.coverPath = coverFile.path;
    } catch (e, s) {
      LogManager.addLog(LogLevel.warning, "IO",
          "Failed to cache cover for ${comic.title}\n$e\n$s");
    }
  }

  /// 删除一个本地漫画（仅从列表移除，不删除原 ZIP 文件）。
  Future<void> remove(String path) async {
    _comics.removeWhere((c) => c.path == path);
    ZipReader.close(path);
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = File(_filePath);
      final json = jsonEncode({
        'comics': _comics.map((c) => c.toMap()).toList(),
      });
      await file.writeAsString(json);
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "IO",
          "Failed to save local comics\n$e\n$s");
    }
  }

  LocalComic? find(String id) {
    for (final c in _comics) {
      if (c.id == id) return c;
    }
    return null;
  }
}
