import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:novel_reader/services/import/lan_transfer_server.dart';

/// 导入选项面板：本地文件 / URL 链接 / 局域网传输。
class ImportOptionsSheet extends StatelessWidget {
  const ImportOptionsSheet({
    super.key,
    required this.onPickLocal,
    required this.onImportUrl,
  });

  final Future<void> Function() onPickLocal;
  final Future<void> Function(String url) onImportUrl;

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function() onPickLocal,
    required Future<void> Function(String url) onImportUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => ImportOptionsSheet(onPickLocal: onPickLocal, onImportUrl: onImportUrl),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('本地文件'),
            subtitle: const Text('支持 txt / md / docx'),
            onTap: () {
              Navigator.pop(context);
              onPickLocal();
            },
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('URL 链接'),
            subtitle: const Text('http/https 直链，单个文件 100MB 以内'),
            onTap: () => _askUrl(context),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('局域网传输'),
            subtitle: const Text('同一 Wi-Fi 下与电脑互传'),
            onTap: () {
              Navigator.pop(context);
              _showLanPanel(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _askUrl(BuildContext context) async {
    final TextEditingController inputController = TextEditingController();
    final String? url = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('输入书籍链接'),
          content: TextField(
            controller: inputController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://.../book.txt'),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, inputController.text.trim()),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    inputController.dispose();
    if (url != null && url.isNotEmpty) {
      await onImportUrl(url);
    }
  }

  void _showLanPanel(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const _LanPanel(),
    );
  }
}

/// 局域网面板：起服务、展示配对二维码（IP + 端口 + 令牌）。
class _LanPanel extends StatefulWidget {
  const _LanPanel();

  @override
  State<_LanPanel> createState() => _LanPanelState();
}

class _LanPanelState extends State<_LanPanel> {
  String? _localIp;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLocalIp();
  }

  Future<void> _loadLocalIp() async {
    final String? ip = await localIpv4();
    if (mounted) {
      setState(() => _localIp = ip);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LanTransferServer server = context.watch<LanTransferServer>();
    final bool running = server.isRunning;
    final String? ip = _localIp;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(running ? '传输服务已开启' : '传输服务未开启',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              running ? '另一端扫描二维码，或访问 http://${ip ?? '?.?.?.?'}:${server.port}' : '开启后另一端可通过扫码互传书籍',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (running && ip != null)
              QrImageView(
                data: server.pairUri(ip),
                version: QrVersions.auto,
                size: 180,
              ),
            if (running && ip != null) ...<Widget>[
              const SizedBox(height: 8),
              Text('配对码：${server.token}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _toggleServer(server),
              icon: Icon(running ? Icons.stop : Icons.play_arrow),
              label: Text(running ? '关闭服务' : '开启服务'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleServer(LanTransferServer server) async {
    setState(() => _busy = true);
    try {
      if (server.isRunning) {
        await server.stop();
      } else {
        await server.start();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

/// 取本机首个非环回 IPv4 地址，用于展示访问入口。
Future<String?> localIpv4() async {
  try {
    final List<NetworkInterface> interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    for (NetworkInterface iface in interfaces) {
      for (InternetAddress addr in iface.addresses) {
        return addr.address;
      }
    }
  } on SocketException {
    return null;
  }
  return null;
}
