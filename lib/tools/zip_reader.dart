import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 本地漫画（ZIP 压缩包）的元数据。
class LocalComic {
  /// ZIP 文件的绝对路径，同时作为唯一 ID。
  final String path;

  /// 显示标题（默认取文件名，去掉扩展名）。
  final String title;

  /// 压缩包内图片文件数量。
  final int pageCount;

  /// 排序后的图片文件名列表（压缩包内的相对路径）。
  final List<String> imageFiles;

  /// 封面缓存文件路径（缩略图），为空表示尚未缓存。
  String? coverPath;

  LocalComic({
    required this.path,
    required this.title,
    required this.pageCount,
    required this.imageFiles,
    this.coverPath,
  });

  String get id => path;

  Map<String, dynamic> toMap() => {
        'path': path,
        'title': title,
        'pageCount': pageCount,
        'imageFiles': imageFiles,
        if (coverPath != null) 'coverPath': coverPath,
      };

  factory LocalComic.fromMap(Map<String, dynamic> map) => LocalComic(
        path: map['path'] as String,
        title: map['title'] as String,
        pageCount: map['pageCount'] as int,
        imageFiles: (map['imageFiles'] as List).cast<String>(),
        coverPath: map['coverPath'] as String?,
      );
}

String _basenameWithoutExtension(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  final name = slash >= 0 ? path.substring(slash + 1) : path;
  final dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(0, dot) : name;
}

const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return '';
  return path.substring(dot);
}

bool _isImage(String name) {
  final ext = _extension(name).toLowerCase();
  return _imageExtensions.contains(ext);
}

// ZIP 签名常量
const _localFileHeaderSignature = 0x04034b50;
const _centralDirectorySignature = 0x02014b50;
const _endOfCentralDirSignature = 0x06054b50;

/// ZIP Central Directory 中一个条目的元信息。
///
/// 仅用于在 [ZipReader] 内部构建索引，不做持久缓存。
class _ZipEntryInfo {
  final String name;
  final int localHeaderOffset;
  final int compressedSize;
  final int uncompressedSize;
  final int compressionMethod; // 0=stored, 8=deflate

  const _ZipEntryInfo({
    required this.name,
    required this.localHeaderOffset,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
  });
}

// ---------- RandomAccessFile 字节级读取辅助 ----------

/// 从 [file] 当前位置读取 2 字节 little-endian 无符号整数。
Future<int> _readUint16(RandomAccessFile file) async {
  final b = await file.read(2);
  return b[0] | (b[1] << 8);
}

/// 从 [file] 当前位置读取 4 字节 little-endian 无符号整数。
Future<int> _readUint32(RandomAccessFile file) async {
  final b = await file.read(4);
  return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24);
}

/// 跳过 [count] 字节。
Future<void> _skip(RandomAccessFile file, int count) async {
  await file.read(count);
}

/// 随机访问 ZIP 读取器。
///
/// 与传统的全量加载方案不同，本实现仅读取 ZIP 文件末尾的
/// Central Directory（中央目录）来构建索引，然后在调用
/// [readImage] 时使用 [RandomAccessFile] seek 到具体条目位置，
/// 只读取和解析当前页的压缩数据。
///
/// 内存占用 ≈ 中央目录大小 + 单页解压后数据，与压缩包总大小无关。
class ZipReader {
  /// 轻量索引缓存：path → (entries, imageNames)
  /// 每个索引条目约 30 字节，不会无限增长。
  static final Map<String, _ZipIndex> _indices = {};

  /// 解析 ZIP 文件，返回 [LocalComic] 元数据。
  /// 若文件不是有效的 ZIP 或没有图片，返回 null。
  static Future<LocalComic?> readComic(String filePath) async {
    try {
      final file = await File(filePath).open(mode: FileMode.read);
      try {
        final length = await file.length();
        final index = await _readCentralDirectory(file, length);
        final imageNames = index.imageNames;
        if (imageNames.isEmpty) return null;

        final title = _basenameWithoutExtension(filePath);

        // 缓存索引供后续按页读取
        _indices[filePath] = index;

        return LocalComic(
          path: filePath,
          title: title,
          pageCount: imageNames.length,
          imageFiles: imageNames,
        );
      } finally {
        await file.close();
      }
    } catch (e) {
      return null;
    }
  }

  /// 读取 ZIP 中指定索引的图片字节。
  ///
  /// 如果索引已缓存，直接 seek 到目标条目位置读取；否则先
  /// 解析 Central Directory 建立索引，再读取目标页面。
  static Future<Uint8List> readImage(String filePath, int index) async {
    final indexData = _indices[filePath];

    if (indexData != null) {
      final entries = indexData.imageEntries;
      final safeIndex = index.clamp(0, entries.length - 1);
      final info = entries[safeIndex];
      final file = await File(filePath).open(mode: FileMode.read);
      try {
        return await _readLocalFileData(file, info);
      } finally {
        await file.close();
      }
    }

    // 索引未缓存，先建立索引再读取
    final file = await File(filePath).open(mode: FileMode.read);
    try {
      final length = await file.length();
      final indexData = await _readCentralDirectory(file, length);
      _indices[filePath] = indexData;

      final entries = indexData.imageEntries;
      final safeIndex = index.clamp(0, entries.length - 1);
      final info = entries[safeIndex];
      return await _readLocalFileData(file, info);
    } finally {
      await file.close();
    }
  }

  /// 关闭某个 ZIP 的索引缓存，释放内存。
  static void close(String filePath) {
    _indices.remove(filePath);
  }

  /// 关闭所有打开的 ZIP 索引缓存。
  static void closeAll() {
    _indices.clear();
  }

  // ---------- Central Directory 解析 ----------

  /// 从 [file] 中读取 EOCD 和 Central Directory，返回图片条目索引。
  static Future<_ZipIndex> _readCentralDirectory(
      RandomAccessFile file, int fileLength) async {
    // 1. 找到 EOCD 记录（在文件末尾附近）
    final eocdOffset = await _findEndOfCentralDirectory(file, fileLength);
    if (eocdOffset < 0) {
      throw const FormatException('End of Central Directory not found');
    }

    // 2. 读取 EOCD 获取 Central Directory 位置
    await file.setPosition(eocdOffset);
    final eocdSignature = await _readUint32(file);
    if (eocdSignature != _endOfCentralDirSignature) {
      throw const FormatException('Invalid EOCD signature');
    }

    // 跳过: diskNumber(2) + diskWithCD(2) + entriesOnDisk(2)
    await _skip(file, 6);
    final totalEntries = await _readUint16(file);
    // centralDirSize(4)
    await _skip(file, 4);
    final centralDirOffset = await _readUint32(file);

    // 3. 读取所有 Central Directory 条目
    await file.setPosition(centralDirOffset);
    final allEntries = <_ZipEntryInfo>[];
    final imageNames = <String>[];
    final imageEntries = <_ZipEntryInfo>[];

    for (int i = 0; i < totalEntries; i++) {
      final entry = await _readCentralDirectoryEntry(file);
      allEntries.add(entry);
      if (_isImage(entry.name)) {
        imageNames.add(entry.name);
        imageEntries.add(entry);
      }
    }

    // 自然排序
    _sortImageEntries(imageNames, imageEntries);

    return _ZipIndex(allEntries, imageNames, imageEntries);
  }

  /// 读取一条 Central Directory 条目。
  static Future<_ZipEntryInfo> _readCentralDirectoryEntry(
      RandomAccessFile file) async {
    final signature = await _readUint32(file);
    if (signature != _centralDirectorySignature) {
      throw const FormatException('Invalid central directory signature');
    }

    // versionMadeBy(2) + versionNeeded(2) + flags(2)
    await _skip(file, 6);
    final compressionMethod = await _readUint16(file);
    // modTime(2) + modDate(2) + crc32(4)
    await _skip(file, 8);
    final compressedSize = await _readUint32(file);
    final uncompressedSize = await _readUint32(file);
    final filenameLength = await _readUint16(file);
    final extraFieldLength = await _readUint16(file);
    final fileCommentLength = await _readUint16(file);
    // diskNumberStart(2) + internalAttrs(2) + externalAttrs(4)
    await _skip(file, 8);
    final localHeaderOffset = await _readUint32(file);

    final nameBytes = await file.read(filenameLength);
    final filename = utf8.decode(nameBytes);

    // 跳过 extra field 和 file comment
    await _skip(file, extraFieldLength + fileCommentLength);

    return _ZipEntryInfo(
      name: filename,
      localHeaderOffset: localHeaderOffset,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      compressionMethod: compressionMethod,
    );
  }

  /// 在文件末尾查找 EOCD 签名。
  ///
  /// EOCD 固定位于文件末尾 65557 字节范围内（因为 comment 最长 65535 字节）。
  /// 从最后 22 字节开始向前搜索签名 0x06054b50。
  static Future<int> _findEndOfCentralDirectory(
      RandomAccessFile file, int fileLength) async {
    const eocdMinSize = 22;
    if (fileLength < eocdMinSize) return -1;

    final searchEnd = fileLength - eocdMinSize;
    final searchStart = (searchEnd > 65557) ? searchEnd - 65557 : 0;

    await file.setPosition(searchStart);
    final searchBytes = await file.read(searchEnd - searchStart);

    // 从后往前找签名
    for (int i = searchBytes.length - eocdMinSize; i >= 0; i--) {
      if (searchBytes[i] == 0x50 &&
          i + 3 < searchBytes.length &&
          searchBytes[i + 1] == 0x4b &&
          searchBytes[i + 2] == 0x05 &&
          searchBytes[i + 3] == 0x06) {
        return searchStart + i;
      }
    }

    return -1;
  }

  // ---------- 数据读取 ----------

  /// 从 [file] 当前位置读取 Local File Header 后的压缩数据并解压。
  ///
  /// [info] 来自 Central Directory 条目，包含压缩方式、大小、偏移等信息。
  static Future<Uint8List> _readLocalFileData(
      RandomAccessFile file, _ZipEntryInfo info) async {
    await file.setPosition(info.localHeaderOffset);

    // 读取并验证 Local File Header 签名
    final signature = await _readUint32(file);
    if (signature != _localFileHeaderSignature) {
      throw const FormatException('Invalid local file header signature');
    }
    // versionNeeded(2) + flags(2) + compressionMethod(2) + modTime(2) +
    // modDate(2) + crc32(4) + compressedSize(4) + uncompressedSize(4)
    await _skip(file, 20);
    final filenameLength = await _readUint16(file);
    final extraFieldLength = await _readUint16(file);
    // 跳过 filename + extra field
    await _skip(file, filenameLength + extraFieldLength);

    // 读取压缩数据
    final compressed = await file.read(info.compressedSize);
    final data = Uint8List.fromList(compressed);

    if (info.compressionMethod == 0) {
      // Stored（未压缩）
      return data;
    } else if (info.compressionMethod == 8) {
      // Deflate
      final codec = ZLibCodec(raw: true);
      final decompressed = codec.decode(data);
      return Uint8List.fromList(decompressed);
    } else {
      throw UnsupportedError(
          'Unsupported ZIP compression method: ${info.compressionMethod}');
    }
  }

  // ---------- 排序 ----------

  static void _sortImageEntries(
      List<String> names, List<_ZipEntryInfo> entries) {
    if (names.length <= 1) return;
    final order = List.generate(names.length, (i) => i);
    order.sort((a, b) => _naturalCompare(names[a], names[b]));

    final sortedNames = <String>[];
    final sortedEntries = <_ZipEntryInfo>[];
    for (final i in order) {
      sortedNames.add(names[i]);
      sortedEntries.add(entries[i]);
    }

    names
      ..clear()
      ..addAll(sortedNames);
    entries
      ..clear()
      ..addAll(sortedEntries);
  }
}

/// 内部索引缓存条目。
class _ZipIndex {
  /// 所有条目的原始列表（含非图片）
  final List<_ZipEntryInfo> allEntries;

  /// 排序后的图片文件名列表
  final List<String> imageNames;

  /// 与 [imageNames] 一一对应
  final List<_ZipEntryInfo> imageEntries;

  const _ZipIndex(this.allEntries, this.imageNames, this.imageEntries);
}

/// 简单的自然排序：按数字大小比较，而非字符串字典序。
int _naturalCompare(String a, String b) {
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ai = a.codeUnitAt(i);
    final bj = b.codeUnitAt(j);
    if (_isDigit(ai) && _isDigit(bj)) {
      // 提取数字
      var ni = i;
      while (ni < a.length && _isDigit(a.codeUnitAt(ni))) {
        ni++;
      }
      var nj = j;
      while (nj < b.length && _isDigit(b.codeUnitAt(nj))) {
        nj++;
      }
      final numA = int.parse(a.substring(i, ni));
      final numB = int.parse(b.substring(j, nj));
      if (numA != numB) return numA.compareTo(numB);
      i = ni;
      j = nj;
    } else {
      if (ai != bj) return ai.compareTo(bj);
      i++;
      j++;
    }
  }
  return a.length.compareTo(b.length);
}

bool _isDigit(int c) => c >= 48 && c <= 57;
