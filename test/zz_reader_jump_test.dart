// 复现用测试 7：阅读页「锚点/跳转只改状态、不移动 PageView」的模式验证（分析工具生成）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复刻 lib/ui/pages/reader_screen.dart 的控制器复用逻辑：
/// 同章节复用 PageController，仅当章节变化时才重建。
class Probe extends StatefulWidget {
  const Probe({super.key});

  @override
  State<Probe> createState() => ProbeState();
}

class ProbeState extends State<Probe> {
  PageController? _pageController;
  int _controllerChapter = 0;
  int pageIndex = 0;
  int chapterIndex = 0;
  int rebuilds = 0;

  PageController _controllerFor(int chapterIndex, int pageIndex) {
    if (_pageController == null || _controllerChapter != chapterIndex) {
      _pageController?.dispose();
      _pageController = PageController(initialPage: pageIndex);
      _controllerChapter = chapterIndex;
    }
    return _pageController!;
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    rebuilds++;
    return MaterialApp(
      home: Scaffold(
        body: PageView.builder(
          key: ValueKey<int>(chapterIndex),
          controller: _controllerFor(chapterIndex, pageIndex),
          itemCount: 10,
          onPageChanged: (int index) => pageIndex = index,
          itemBuilder: (BuildContext context, int index) =>
              Center(child: Text('page-$index', key: ValueKey<String>('p$index'))),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('R18 锚点跳转在同一章节内是否真的移动视图', (WidgetTester tester) async {
    final GlobalKey<ProbeState> key = GlobalKey<ProbeState>();
    await tester.pumpWidget(Probe(key: key));
    await tester.pumpAndSettle();
    print('R18 initial visible: ${tester.widget<Text>(find.textContaining('page-')).data}');

    // 模拟 jumpTo / 目录跳章：只改状态并 setState（reader 中为 notifyListeners）
    key.currentState!.setState(() => key.currentState!.pageIndex = 5);
    await tester.pumpAndSettle();
    print('R18 pageIndex=5 之后可见: ${tester.widget<Text>(find.textContaining('page-')).data}');

    // 只有显式调用 jumpToPage 才会移动
    key.currentState!._pageController!.jumpToPage(5);
    await tester.pumpAndSettle();
    print('R18 jumpToPage(5) 之后可见: ${tester.widget<Text>(find.textContaining('page-')).data}');
  });
}
