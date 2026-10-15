import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:novel_reader/models/source_manifest.dart';
import 'package:novel_reader/services/source/source_registry.dart';
import 'package:novel_reader/state/source_controller.dart';

/// 数据源管理：安装 / 启停 / 查看状态与错误 / 导出 / 卸载。
///
/// 对照上游的插件管理页，这里省掉了「签名校验、assets 解包、App 插件扫描」
/// 这些 Android 专有动作，但保留了它的核心信息结构：
/// **状态一眼可见、失败原因直接摊开、能装能删能停用**。
class SourceManagerPage extends StatelessWidget {
  const SourceManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SourceController controller = context.watch<SourceController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据源'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: '安装数据源',
            icon: const Icon(Icons.add),
            onSelected: (String action) => _onInstallAction(context, action),
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'sample',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.auto_awesome),
                  title: Text('安装内置示例源'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'paste',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.content_paste),
                  title: Text('粘贴 JSON 声明'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'file',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.folder_open),
                  title: Text('从文件导入'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'docs',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.help_outline),
                  title: Text('怎么写自己的源'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 80),
              children: <Widget>[
                const _IntroCard(),
                if (controller.entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('还没有安装任何数据源',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                for (final SourceEntry entry in controller.entries)
                  _SourceCard(
                    entry: entry,
                    isActive: controller.activeSourceId == entry.id,
                    onToggle: (bool value) => controller.setEnabled(entry.id, value),
                    onActivate: () => controller.setActiveSource(entry.id),
                    onRemove: () => _confirmRemove(context, controller, entry),
                    onExport: () => _export(context, controller, entry),
                    onRetry: () => controller.load(),
                  ),
              ],
            ),
    );
  }

  Future<void> _onInstallAction(BuildContext context, String action) async {
    final SourceController controller = context.read<SourceController>();
    switch (action) {
      case 'sample':
        final SourceInstallResult result = await controller.installSample();
        if (context.mounted) {
          _showResult(context, result);
        }
      case 'file':
        final PlatformFile? file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: <String>['json'],
        );
        final String? path = file?.path;
        if (path == null) {
          return;
        }
        final SourceInstallResult result = await controller.installFromFile(path);
        if (context.mounted) {
          _showResult(context, result);
        }
      case 'paste':
        if (!context.mounted) {
          return;
        }
        final String? text = await _askJson(context);
        if (text == null || text.trim().isEmpty) {
          return;
        }
        final SourceInstallResult result = await controller.install(text);
        if (context.mounted) {
          _showResult(context, result);
        }
      case 'docs':
        if (!context.mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('怎么写自己的源'),
            content: const SingleChildScrollView(
              child: Text(
                '一个源就是一份 JSON 声明，核心是「用选择器描述页面结构」：\n\n'
                '• capabilities：声明支持哪些能力（search/explore/bookInfo/volumes/chapter）\n'
                '• baseUrl + charset：站点地址与编码（中文站点常是 gb18030）\n'
                '• 各能力下的 path：URL 模板，{id} / {chapterId} / {q} / {page} / {extra} 会被替换\n'
                '• fields：字段名 → "选择器@属性|算子"。算子支持 trim、absUrl、number、'
                'regex:模式、replace:旧,新\n\n'
                '最小可用声明只需要 bookInfo + volumes + chapter，'
                '于是「搜索到 → 看目录 → 读正文」这条链路就通了。\n\n'
                '建议先安装内置示例源，把它导出来对着改。',
                style: TextStyle(fontSize: 13),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
    }
  }

  Future<String?> _askJson(BuildContext context) {
    final TextEditingController textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('粘贴源声明'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: textController,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '{"id":"my.source", ...}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, textController.text),
            child: const Text('安装'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    SourceController controller,
    SourceEntry entry,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('卸载数据源'),
        content: Text('卸载《${entry.name}》会同时清掉它的章节缓存；'
            '已经导入书架的书不受影响，仍可离线阅读。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.remove(entry.id);
    }
  }

  Future<void> _export(
    BuildContext context,
    SourceController controller,
    SourceEntry entry,
  ) async {
    final String json = controller.exportManifest(entry.id);
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('源声明已复制到剪贴板')),
      );
    }
  }

  static void _showResult(BuildContext context, SourceInstallResult result) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result.message),
      duration: const Duration(seconds: 4),
    ));
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 6),
                  Text('数据源是一份 JSON 声明',
                      style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                '不用编译、不用安装 APK：描述清楚「URL 模板 + CSS 选择器」就能接入一个站点。'
                '每个源彼此隔离，切换源不会影响别的源的数据。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.entry,
    required this.isActive,
    required this.onToggle,
    required this.onActivate,
    required this.onRemove,
    required this.onExport,
    required this.onRetry,
  });

  final SourceEntry entry;
  final bool isActive;
  final Future<void> Function(bool value) onToggle;
  final VoidCallback onActivate;
  final Future<void> Function() onRemove;
  final Future<void> Function() onExport;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SourceManifest? manifest = entry.manifest;
    final bool healthy = entry.status == SourceStatus.ready;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          entry.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('使用中', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      entry.id,
                      if (manifest != null) 'API ${manifest.apiVersion}',
                      if (manifest != null && manifest.versionName.isNotEmpty)
                        'v${manifest.versionName}',
                      SourceController.describeStatus(entry.status),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (manifest != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(SourceController.describeCapabilities(manifest),
                        style: theme.textTheme.bodySmall),
                  ],
                  if (entry.error.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      entry.error,
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: <Widget>[
                Switch(
                  value: entry.record.enabled,
                  onChanged: healthy || !entry.record.enabled
                      ? (bool value) => onToggle(value)
                      : null,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onSelected: (String action) {
                    switch (action) {
                      case 'activate':
                        onActivate();
                      case 'export':
                        onExport();
                      case 'retry':
                        onRetry();
                      case 'remove':
                        onRemove();
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    if (healthy)
                      const PopupMenuItem<String>(
                        value: 'activate',
                        child: Text('设为当前源'),
                      ),
                    const PopupMenuItem<String>(
                      value: 'export',
                      child: Text('复制声明'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'retry',
                      child: Text('重新加载'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'remove',
                      child: Text('卸载'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
