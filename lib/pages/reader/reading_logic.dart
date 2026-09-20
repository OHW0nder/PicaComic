part of pica_reader;

extension PageControllerExtension on PageController{
  void animatedJumpToPage(int page){
    final current = this.page?.round() ?? 0;
    if((current - page).abs() > 1){
      jumpToPage(page > current ? page - 1 : page + 1);
    }
    animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.ease);
  }

  void jumpByDeviceType(int page) {
    if(StateController.find<ComicReadingPageLogic>().mouseScroll) {
      jumpToPage(page);
    } else {
      animatedJumpToPage(page);
    }
  }
}

class ComicReadingPageLogic extends StateController {
  ///控制页面, 用于非从上至下(连续)阅读方式
  late PageController pageController;

  ///用于从上至下(连续)阅读方式, 跳转至指定项目
  var itemScrollController = ItemScrollController();

  ///用于从上至下(连续)阅读方式, 获取当前滚动到的元素的序号
  var itemScrollListener = ItemPositionsListener.create();

  ///用于从上至下(连续)阅读方式, 控制滚动
  var scrollController = ScrollController(keepScrollOffset: true);

  ///用于从上至下(连续)阅读方式, 获取放缩大小
  PhotoViewController get photoViewController => photoViewControllers[index]
      ?? photoViewControllers[0]!;

  var photoViewControllers = <int, PhotoViewController>{};

  ListenVolumeController? listenVolume;

  ScrollManager? scrollManager;

  String? errorMessage;

  void clearPhotoViewControllers(){
    photoViewControllers.forEach((key, value) => value.dispose());
    photoViewControllers.clear();
  }

  bool noScroll = false;

  bool mouseScroll = false;

  double currentScale = 1.0;

  bool get isCtrlPressed => HardwareKeyboard.instance.isControlPressed;

  List<bool> requestedLoadingItems = [];

  bool haveUsedInitialPage = false;

  /// 双页模式下是否在第一页时显示单页
  bool get singlePageForFirstScreen => appdata.implicitData[1] == '1';

  var focusNode = FocusNode();

  static int _getIndex(int initPage) {
    if (appdata.settings[9] == "5" || appdata.settings[9] == "6") {
      return initPage % 2 == 1 ? initPage : initPage - 1;
    } else {
      return initPage;
    }
  }

  static int _getPage(int initPage) {
    if (appdata.settings[9] == "5" || appdata.settings[9] == "6") {
      return (initPage + 2) ~/ 2;
    } else {
      return initPage;
    }
  }

  ComicReadingPageLogic(this.order, this.data, int initialPage, this.updateHistory){
    if(initialPage <= 0){
      initialPage = 1;
    }
    pageController =
        PageController(initialPage: _getPage(initialPage));
    _index = _getIndex(initialPage);
    order <= 0 ? order = 1 : order;
    itemScrollListener.itemPositions.addListener(() {
      var newIndex = itemScrollListener.itemPositions.value.first.index + 1;
      if(newIndex != index) {
        index = newIndex;
        update(["ToolBar"]);
      }
    });
  }


  final void Function() updateHistory;

  ReadingData data;

  bool isLoading = true;

  ///旋转方向: null-跟随系统, false-竖向, true-横向
  bool? rotation;

  ///是否应该显示悬浮按钮, 为-1表示显示上一章, 为0表示不显示, 为1表示显示下一章
  int showFloatingButtonValue = 0;

  double fABValue = 0;

  void showFloatingButton(int value) {
    if (value == 0) {
      if (showFloatingButtonValue != 0) {
        showFloatingButtonValue = 0;
        fABValue = 0;
        update();
      }
    }
    if (value == 1 && showFloatingButtonValue == 0) {
      showFloatingButtonValue = 1;
      update();
    } else if (value == -1 && showFloatingButtonValue == 0 && order != 1) {
      showFloatingButtonValue = -1;
      update();
    }
  }

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  late int _index;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  int get index => _index;

  ///当前的页面, 0和最后一个为空白页, 用于进行章节跳转
  set index(int value) {
    _index = value;
    // 多话续接时, 根据全局页码自动更新当前章节序号
    if (_epStarts.isNotEmpty) {
      var newOrder = epOrderAt(value - 1);
      if (newOrder != order) {
        order = newOrder;
      }
    }
    for (var element in _indexChangeCallbacks) {
      element(value);
    }
    updateHistory();
  }

  final _indexChangeCallbacks = <void Function(int)>[];

  void addIndexChangeCallback(void Function(int) callback){
    _indexChangeCallbacks.add(callback);
  }

  void removeIndexChangeCallback(void Function(int) callback){
    _indexChangeCallbacks.remove(callback);
  }

  ///当前的章节位置, 从1开始
  int order;

  ///工具栏是否打开
  bool tools = false;

  ///是否显示设置窗口
  bool showSettings = false;

  ///所有的图片链接(自动续接下一话时, 为多话拼接后的列表)
  var urls = <String>[];

  ///已拼接章节的第一页在 [urls] 中的偏移(0基), 键为章节序号(从1开始)
  final Map<int, int> _epStarts = {};

  ///最后拼接的章节序号
  int _lastAppendedOrder = 0;

  ///内容版本号, 异步续接完成时用于判断内容是否已被章节切换重置
  int _contentGeneration = 0;

  ///正在进行的续接请求, 并发调用复用同一个 Future
  Future<bool>? _pendingAppend;

  ///重置内容为空(章节切换/重新加载时调用)
  void resetContent() {
    _contentGeneration++;
    _epStarts.clear();
    _lastAppendedOrder = 0;
    _pendingAppend = null;
    urls = [];
  }

  ///将内容设置为单一章节(初次加载时调用)
  void setContent(int epOrder, List<String> epUrls) {
    _contentGeneration++;
    _epStarts.clear();
    _epStarts[epOrder] = 0;
    _lastAppendedOrder = epOrder;
    _pendingAppend = null;
    // 复制成可增长列表: 本地 ZIP、已下载漫画的 loadEp 返回的是
    // List.filled 生成的定长列表, 直接使用会导致续接时 addAll 失败
    urls = List.of(epUrls);
  }

  ///全局页码(0基)对应的章节序号
  int epOrderAt(int globalPage) {
    if (_epStarts.isEmpty) {
      return order;
    }
    int result = _lastAppendedOrder;
    for (var entry in _epStarts.entries) {
      if (globalPage >= entry.value) {
        result = entry.key;
      }
    }
    return result;
  }

  ///全局页码(0基)对应章节内的局部页码(0基)
  int localPageAt(int globalPage) {
    var ep = epOrderAt(globalPage);
    return globalPage - (_epStarts[ep] ?? 0);
  }

  ///已拼接的指定章节的页数
  int epLength(int epOrder) {
    int start = _epStarts[epOrder] ?? 0;
    int? nextStart;
    for (var entry in _epStarts.entries) {
      if (entry.key > epOrder) {
        nextStart = entry.value;
        break;
      }
    }
    return (nextStart ?? urls.length) - start;
  }

  ///是否还有可以自动续接的下一话
  bool get hasEpToAppend =>
      data.hasEp &&
      _lastAppendedOrder > 0 &&
      _lastAppendedOrder < (data.eps?.length ?? 0);

  ///自动续接下一话: 将下一话内容拼接到当前内容末尾, 成功返回true
  ///
  ///已有续接请求在途时复用该请求: 自动翻页需要等待续接结果,
  ///不能把"正在续接"和"没有下一话"一样当作失败, 否则会停在本话末尾.
  Future<bool> appendNextEp() {
    final pending = _pendingAppend;
    if (pending != null) {
      return pending;
    }
    if (!hasEpToAppend) {
      log("跳过续接: hasEp=${data.hasEp} 当前话=$_lastAppendedOrder "
          "总话数=${data.eps?.length} 已加载页数=${urls.length}", "续接");
      return Future.value(false);
    }
    late final Future<bool> future;
    future = _appendNextEp().whenComplete(() {
      // 结束(包括失败)后清空在途标记, 使后续调用可以重新尝试;
      // 若期间已被新的续接请求或章节切换替换, 则不动它
      if (identical(_pendingAppend, future)) {
        _pendingAppend = null;
      }
    });
    _pendingAppend = future;
    return future;
  }

  Future<bool> _appendNextEp() async {
    int nextOrder = _lastAppendedOrder + 1;
    int generation = _contentGeneration;
    log("开始续接第 $nextOrder 话(总话数=${data.eps?.length}, 已加载页数=${urls.length})",
        "续接");
    Res<List<String>> res;
    try {
      res = await data.loadEp(nextOrder);
    } catch (e, s) {
      // 加载抛异常不能让自动翻页静默中断
      log("第 $nextOrder 话加载抛异常: $e\n$s", "续接", LogLevel.error);
      return false;
    }
    if (generation != _contentGeneration) {
      // 期间发生了章节切换, 丢弃结果
      log("丢弃第 $nextOrder 话结果: 期间发生了章节切换", "续接");
      return false;
    }
    if (res.error) {
      log("第 $nextOrder 话加载失败: ${res.errorMessageWithoutNull}", "续接",
          LogLevel.error);
      return false;
    }
    // 先并入内容再更新记录: 并入失败时不留下"下一话已拼接"的错位状态
    final start = urls.length;
    urls.addAll(res.data);
    _epStarts[nextOrder] = start;
    _lastAppendedOrder = nextOrder;
    log("第 $nextOrder 话已拼接 ${res.data.length} 页, 共 ${urls.length} 页", "续接");
    update();
    return true;
  }

  ///加载全局页码(0基)对应的图片(多话续接时自动映射到对应章节)
  Stream<DownloadProgress> loadImageAt(int globalPage) {
    return data.loadImage(
        epOrderAt(globalPage), localPageAt(globalPage), urls[globalPage]);
  }

  void reload() {
    index = 1;
    pageController = PageController(initialPage: 1);
    isLoading = true;
    update();
  }

  void change() {
    isLoading = !isLoading;
    update();
  }

  ReadingMethod get readingMethod =>
      ReadingMethod.values[int.parse(appdata.settings[9]) - 1];

  void jumpToNextPage() {
    if (readingMethod.index < 3) {
      pageController.jumpToPage(index + 1);
    } else if (readingMethod == ReadingMethod.topToBottomContinuously) {
      scrollController.jumpTo(scrollController.position.pixels + 600);
    } else {
      pageController.jumpToPage(pageController.page!.round() + 1);
    }
  }

  void jumpToLastPage() {
    if (readingMethod.index < 3) {
      pageController.jumpToPage(index - 1);
    } else if (readingMethod == ReadingMethod.topToBottomContinuously) {
      scrollController.jumpTo(scrollController.position.pixels - 600);
    } else {
      pageController.jumpToPage(pageController.page!.round() - 1);
    }
  }

  void jumpToPage(int i, [bool updateWidget = false]) {
    i = i.clamp(1, length);
    if (readingMethod == ReadingMethod.topToBottomContinuously) {
      itemScrollController.jumpTo(index: i - 1);
    } else if(!readingMethod.isTwoPage){
      pageController.jumpToPage(i);
    } else {
      var index = singlePageForFirstScreen ? i ~/ 2 + 1 : (i + 1) ~/ 2;
      pageController.jumpToPage(index);
    }
    if(index != i){
      index = i;
    }
    if(updateWidget){
      update(["ToolBar"]);
    }
  }

  void jumpByDeviceType(int page){
    Future.microtask(() {
      if(mouseScroll){
        pageController.jumpToPage(page);
      } else {
        pageController.animatedJumpToPage(page);
      }
    });
  }

  void jumpToNextChapter() {
    var eps = data.eps;
    showFloatingButtonValue = 0;
    if (!data.hasEp || order == eps?.length) {
      if(readingMethod != ReadingMethod.topToBottomContinuously){
        if (readingMethod.index < 3) {
          jumpByDeviceType(urls.length);
        } else if (readingMethod == ReadingMethod.twoPage) {
          jumpByDeviceType((urls.length % 2 + urls.length) ~/ 2);
        }
      } else {
        jumpToPage(urls.length);
        index = urls.length;
        update(["ToolBar"]);
      }
      return;
    }
    // 下一话已续接到当前内容时, 直接跳转到下一话第一页, 无需重新加载
    int? nextStart = _epStarts[order + 1];
    if (nextStart != null) {
      jumpToPage(nextStart + 1, true);
      return;
    }
    order += 1;
    resetContent();
    isLoading = true;
    tools = false;
    index = 1;
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
    update();
  }

  void jumpToChapter(int index){
    order = index;
    resetContent();
    isLoading = true;
    tools = false;
    this.index = 1;
    pageController = PageController(initialPage: 1);
    clearPhotoViewControllers();
    update();
  }

  void jumpToLastChapter() {
    showFloatingButtonValue = 0;
    if(order == 1 || !data.hasEp){
      if(readingMethod != ReadingMethod.topToBottomContinuously){
        jumpByDeviceType(1);
      } else {
        jumpToPage(1);
        index = 1;
        update(["ToolBar"]);
      }
      return;
    }
    // 上一话已续接在当前内容中时, 直接跳转到上一话最后一页, 无需重新加载
    int? prevStart = _epStarts[order - 1];
    if (prevStart != null) {
      jumpToPage(prevStart + epLength(order - 1), true);
      return;
    }

    order -= 1;
    resetContent();
    isLoading = true;
    tools = false;
    pageController = PageController(initialPage: 1);
    index = 1;
    clearPhotoViewControllers();
    update();
  }

  ///当前章节的长度
  int get length => urls.length;

  /// 是否处于自动翻页状态
  bool runningAutoPageTurning = false;

  /// 用户刚刚拖拽结束，autoPageTurning 应等待弹跳结束再恢复
  bool _userWasDragging = false;

  /// 自动翻页
  void autoPageTurning() async {
    if (!runningAutoPageTurning) {
      return;
    }
    if (readingMethod != ReadingMethod.topToBottomContinuously &&
        index >= urls.length - 1) {
      // 已到本话末尾, 尝试自动续接下一话
      if (!runningAutoPageTurning || !await appendNextEp()) {
        runningAutoPageTurning = false;
        update();
        return;
      }
    }
    int sec = int.parse(appdata.settings[33]);
    if (readingMethod == ReadingMethod.topToBottomContinuously) {
      // 连续模式：单次平滑上滑到本话结束，拖拽时暂停，松手后继续
      double viewportHeight = scrollController.position.viewportDimension;

      outer:
      while (runningAutoPageTurning) {
        while (runningAutoPageTurning) {
          // 用户刚拖拽完？等待弹跳完全结束
          if (_userWasDragging) {
            if (!scrollController.position.isScrollingNotifier.value) {
              _userWasDragging = false;
            }
            await Future.delayed(const Duration(milliseconds: 50));
            continue;
          }
          // 每次重新读取终点: 续接进来的下一话会让列表变长, 终点随之改变,
          // 用旧终点判断会把"还没读完"当成"已到末尾"而停下
          double maxScroll = scrollController.position.maxScrollExtent;
          double remaining = maxScroll - scrollController.position.pixels;
          if (remaining <= 1) {
            break;
          }
          double totalSec = (remaining / viewportHeight) * sec;
          try {
            await scrollController.animateTo(
              maxScroll,
              duration:
                  Duration(milliseconds: (totalSec * 1000).round()),
              curve: Curves.linear,
            );
            // animateTo 正常返回不代表到了终点（被手势中断也会正常返回），
            // 由下一轮循环重新读取位置判断
          } catch (_) {
            // 被中断（点击或拖拽），短暂等待后循环重新开始
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
        if (!runningAutoPageTurning) {
          return;
        }
        // 到达本话末尾, 尝试自动续接下一话, 续接后继续滚动
        if (await appendNextEp()) {
          // 等待列表完成布局, 使 maxScrollExtent 反映新增内容
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        log("自动翻页停止: 已到内容末尾且无下一话可续接(位置="
            "${scrollController.position.pixels.toStringAsFixed(0)}/"
            "${scrollController.position.maxScrollExtent.toStringAsFixed(0)})", "续接");
        break outer;
      }
      runningAutoPageTurning = false;
      update();
      return;
    }
    if (readingMethod == ReadingMethod.topToBottom) {
      // 非连续模式：先等待观看，再平滑翻到下一页
      for (int i = 0; i < sec * 10; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!runningAutoPageTurning) {
          return;
        }
      }
      if (index >= urls.length - 1) {
        // 已到本话末尾, 尝试自动续接下一话
        if (!await appendNextEp()) {
          runningAutoPageTurning = false;
          update();
          return;
        }
      }
      try {
        await pageController.animateToPage(
          index + 1,
          duration: const Duration(milliseconds: 500),
          curve: Curves.linear,
        );
      } catch (_) {
        // 动画被用户操作中断
      }
      if (runningAutoPageTurning) {
        autoPageTurning();
      }
      return;
    }
    for (int i = 0; i < sec * 10; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (!runningAutoPageTurning) {
        return;
      }
    }
    jumpToNextPage();
    autoPageTurning();
  }

  void refresh_() {
    pageController = PageController(initialPage: 1);
    itemScrollController = ItemScrollController();
    itemScrollListener = ItemPositionsListener.create();
    scrollController = ScrollController(keepScrollOffset: true);
    clearPhotoViewControllers();
    noScroll = false;
    currentScale = 1.0;
    showFloatingButtonValue = 0;
    index = 1;
    resetContent();
    isLoading = true;
    tools = false;
    showSettings = false;
    update();
  }

  bool isFullScreen = false;

  void fullscreen(){
    const channel = MethodChannel("pica_comic/full_screen");
    channel.invokeMethod("set", !isFullScreen);
    isFullScreen = !isFullScreen;
    focusNode.requestFocus();

    if(isFullScreen){
      StateController.find<WindowFrameController>().hideWindowFrame();
    } else {
      StateController.find<WindowFrameController>().showWindowFrame();
    }
  }

  void handleKeyboard(KeyEvent event) {
    if(event is KeyDownEvent || event is KeyRepeatEvent){
      bool reverse = appdata.settings[9] == "2" || appdata.settings[9] == "6";
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.arrowRight:
          reverse ? jumpToLastPage(): jumpToNextPage();
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.arrowLeft:
          reverse ? jumpToNextPage(): jumpToLastPage();
        case LogicalKeyboardKey.f12:
          fullscreen();
      }
    }
  }

  late final void Function() openEpsView;
}
