import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/local_comics.dart';
import 'package:pica_comic/foundation/image_loader/zip_image_provider.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/tools/zip_reader.dart';

class LocalComicPageLogic extends StateController {
  List<LocalComic> comics = [];
  bool loading = true;
  bool importing = false;

  void reload() async {
    await LocalComicsManager().load();
    comics = LocalComicsManager().comics;
    loading = false;
    update();
  }

  void import() async {
    if (importing) return;
    importing = true;
    update();
    try {
      const typeGroup = XTypeGroup(
        label: 'ZIP',
        extensions: <String>['zip'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) {
        importing = false;
        update();
        return;
      }
      final path = file.path;
      final comic = await LocalComicsManager().import(path);
      if (comic == null) {
        showToast(message: "导入失败: 无法读取ZIP或未找到图片".tl);
      } else {
        showToast(message: "导入成功".tl);
        comics = LocalComicsManager().comics;
      }
    } catch (e) {
      showToast(message: "导入失败: $e".tl);
    } finally {
      importing = false;
      update();
    }
  }

  void remove(LocalComic comic) async {
    showConfirmDialog(
      App.globalContext!,
      "确认删除".tl,
      "将从本地漫画列表移除（不会删除原ZIP文件）, 是否继续?".tl,
      () {
        App.globalBack();
        LocalComicsManager().remove(comic.path).then((_) {
          comics = LocalComicsManager().comics;
          update();
        });
      },
    );
  }

  void read(LocalComic comic) {
    App.globalTo(
      () => ComicReadingPage.local(comic, 1),
    );
  }
}

class LocalComicPage extends StatelessWidget {
  const LocalComicPage({super.key});

  @override
  Widget build(BuildContext context) {
    var logic = StateController.putIfNotExists<LocalComicPageLogic>(
        LocalComicPageLogic());
    if (logic.loading) {
      logic.reload();
    }
    return Scaffold(
      appBar: AppBar(
        title: Text("本地漫画".tl),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // 预留搜索入口
            },
          ),
          IconButton(
            icon: logic.importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_upload_outlined),
            tooltip: "导入".tl,
            onPressed: logic.importing ? null : () => logic.import(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "LocalComicImport",
        onPressed: logic.importing ? null : () => logic.import(),
        child: const Icon(Icons.add),
      ),
      body: StateBuilder<LocalComicPageLogic>(builder: (logic) {
        if (logic.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (logic.comics.isEmpty) {
          return _buildEmpty(context);
        }
        return SmoothCustomScrollView(
          slivers: [
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                childCount: logic.comics.length,
                (context, index) {
                  final comic = logic.comics[index];
                  return _LocalComicTile(
                    comic: comic,
                    onTap: () => logic.read(comic),
                    onLongPress: () => logic.remove(comic),
                  );
                },
              ),
              gridDelegate: SliverGridDelegateWithComics(),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text("还没有本地漫画".tl),
          const SizedBox(height: 8),
          Text(
            "点击右下角 + 导入 ZIP 压缩包".tl,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalComicTile extends StatelessWidget {
  const _LocalComicTile({
    required this.comic,
    required this.onTap,
    required this.onLongPress,
  });

  final LocalComic comic;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        child: Image(
                          image: ZipImageProvider(comic.path, 0),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stack) {
                            return const Center(
                              child: Icon(Icons.broken_image, size: 40),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "${comic.pageCount}P",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              comic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              "${comic.pageCount} 页",
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
