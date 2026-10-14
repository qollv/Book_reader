# novel_reader — 手机小说阅读器

Flutter 跨平台小说阅读软件：本地导入 txt / md / docx 并智能排版，支持 URL / 局域网远程导入，书架管理、进度同步、书签笔记、夜间模式与字体调整。

> **下载调试版 APK**：[Releases → v0.1.0-debug](https://github.com/qollv/Book_reader/releases/tag/v0.1.0-debug)（153MB，含全部 ABI；传到手机点击安装即可）

完整设计方案见 [docs/项目计划书.md](docs/项目计划书.md)。

## 功能一览

- **智能排版**：段落重排（txt 硬换行按句读续行合并，中英混排自动补空格）、章节识别、首行缩进、标题 keep-with-next、孤行控制、按屏幕实时分页；分页预算与渲染共用同一套块级度量（BlockMetrics），分页结果即视觉结果
- **编码兼容**：UTF-8 / UTF-8 BOM / UTF-16 / GBK-GB18030 自动识别回退，二进制文件给出中文错误提示
- **远程导入**：URL 直链下载（下载前预检大小、30s 超时）、局域网互传（扫码配对 + 令牌鉴权 + 路径穿越防护 + 端口占用自动退让）、云端进度同步（端点/令牌用户自配，last-write-wins 合并）
- **书架**：网格书架、阅读百分比、长按删书（连带清进度/书签/笔记）
- **阅读器**：滑动或滚动翻页、进度滑块、目录跳章、书签、长按记笔记、打开失败错误页
- **外观**：5 套配色（含夜间）、字体/字号/行距/边距可调，即时持久化；设置数据带校验与 clamp，脏数据不会导致启动崩溃
- **进度同步**：锚点式进度（章+段+行）重排版不错位；写库防抖 300ms；多设备按设备 UUID 合并

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

- 云端同步需用户自备服务端（首次点同步会弹出地址/令牌配置框）；删除操作不在设备间传播（防误删）
- 局域网传输目前只有"本机起服务、对端扫码/HTTP 连接"方向，App 内暂无扫码客户端入口
- Web 平台仅验证过编译（`flutter build web`），运行时未支持：持久化依赖 sqflite、正文读写依赖 dart:io
- docx 仅提取正文文本（含 Word 标题样式识别），图片/复杂表格忽略
- 分页结果按「bookId|章节|排版参数」LRU 缓存（上限 12 章），不是持久化缓存
