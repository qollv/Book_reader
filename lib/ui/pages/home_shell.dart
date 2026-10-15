import 'package:flutter/material.dart';

import 'package:novel_reader/ui/pages/bookshelf_page.dart';
import 'package:novel_reader/ui/pages/explore_page.dart';

/// 应用主框架：书架 / 探索两个入口。
///
/// 用 [IndexedStack] 而不是按需构建：切来切去时保留滚动位置与已加载的书单，
/// 这对探索页尤其重要——每次回来都重新抓一遍首页既慢又费流量。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          BookshelfPage(),
          ExplorePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: '探索',
          ),
        ],
      ),
    );
  }
}
