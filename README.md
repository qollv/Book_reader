# novel_reader — 手机小说阅读器

Flutter 跨平台小说阅读软件：本地导入 txt / md / docx 并智能排版，支持 URL / 局域网远程导入，书架管理、进度同步、书签笔记、夜间模式与字体调整。

完整设计方案见 [docs/项目计划书.md](docs/项目计划书.md)。

## 功能一览

- **智能排版**：段落重排（txt 硬换行合并）、章节识别、首行缩进、标题 keep-with-next、孤行控制、按屏幕实时分页
- **远程导入**：URL 直链下载 / 局域网扫码互传 / 云端同步（LAN + HTTP 两种通道）
- **书架**：网格书架、阅读百分比、长按删书（连带清进度/书签/笔记）
- **阅读器**：滑动或滚动翻页、进度滑块、目录跳章、长按记笔记
- **外观**：5 套配色（含夜间）、字体/字号/行距/页边距/翻页方式可调，即时持久化
- **进度同步**：锚点式进度（章+段+行），重排版后不错位；多设备 last-write-wins 合并

## 快速开始

```bash
cd novel_reader
flutter pub get
flutter run
```

运行测试：

```bash
flutter test
```

## 目录结构

```
lib/
├── main.dart               # 依赖装配与启动
├── models/                 # 数据模型（Book/Chapter/Progress/Bookmark/Note/Settings）
├── core/
│   ├── text/               # txt 续行合并
│   ├── parsers/            # txt / md / docx 解析器
│   └── pagination/         # TextPainter 分页引擎
├── data/
│   ├── app_database.dart   # sqflite 建库
│   ├── dao/                # 各表 DAO
│   └── repositories/       # 仓库层
├── services/
│   ├── import/             # 本地 / URL / 局域网导入
│   └── sync/               # 同步合并 + 传输通道
├── state/                  # Settings / Bookshelf / Reader 控制器
└── ui/                     # 页面与组件
```

## 环境要求

- Flutter 3.24+ / Dart 3.4+
- Android 5.0+ / iOS 12+

## 已知限制

- docx 仅提取正文文本，图片与复杂表格忽略
- 淡入翻页暂复用滑动动画
- 云端同步需用户自备服务端
