import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:novel_reader/core/source/source_engine.dart';
import 'package:novel_reader/data/dao/source_dao.dart';
import 'package:novel_reader/services/source/source_registry.dart';

import '../support/fake_http_fetcher.dart';
import '../support/test_database.dart';

String manifestJson({
  String id = 'test.src',
  String name = '测试源',
  int apiVersion = 4,
  int versionCode = 1,
  String charset = 'utf-8',
}) {
  return jsonEncode(<String, Object?>{
    'id': id,
    'name': name,
    'apiVersion': apiVersion,
    'versionCode': versionCode,
    'baseUrl': 'https://ex.com',
    'charset': charset,
    'capabilities': <String>['chapter'],
    'chapter': <String, Object?>{'path': '/read/{chapterId}', 'content': '#content p'},
  });
}

void main() {
  late Database db;
  late SourceDao dao;
  late FakeHttpFetcher fetcher;
  late SourceRegistry registry;

  setUp(() async {
    db = await openTestDatabase();
    dao = SourceDao(db);
    fetcher = FakeHttpFetcher();
    registry = SourceRegistry(dao: dao, fetcher: fetcher);
    await registry.load();
  });

  tearDown(() async {
    await registry.dispose();
    await db.close();
  });

  group('安装门控', () {
    test('合法声明安装成功并可用', () async {
      final SourceInstallResult result = await registry.install(manifestJson());

      expect(result.ok, isTrue, reason: result.message);
      expect(registry.usableEntries.length, 1);
      final SourceEntry entry = registry.entryOf('test.src')!;
      expect(entry.status, SourceStatus.ready);
      expect(entry.name, '测试源');
      expect(registry.engineFor('test.src'), isNotNull);
      expect(entry.engine!.manifest.id, 'test.src');
    });

    test('JSON 语法错误被拒，且不动库里已有数据', () async {
      await registry.install(manifestJson());

      final SourceInstallResult broken = await registry.install('{ not json');
      expect(broken.ok, isFalse);
      expect(broken.message, contains('JSON'));
      expect(registry.usableEntries.length, 1, reason: '坏更新不能弄坏已装好的源');
    });

    test('声明缺字段被拒，并给出字段名', () async {
      final SourceInstallResult result = await registry.install(jsonEncode(<String, Object?>{
        'name': '缺 id',
        'baseUrl': 'https://ex.com',
      }));

      expect(result.ok, isFalse);
      expect(result.message, contains('id'));
    });

    test('跨组 API 版本被拒（带可读原因）', () async {
      final SourceInstallResult result = await registry.install(manifestJson(apiVersion: 1));

      expect(result.ok, isFalse);
      expect(result.message, contains('1'));
      expect(result.message, contains('不被支持'));
    });

    test('源版本高于宿主被拒', () async {
      // 宿主是 4，声明 3（同组但更低）可以；声明 5 不在分组表里 → 拒
      final SourceInstallResult result = await registry.install(manifestJson(apiVersion: 5));
      expect(result.ok, isFalse);
    });

    test('防降级：已装高版本时拒绝安装低版本', () async {
      await registry.install(manifestJson(versionCode: 5));

      final SourceInstallResult downgrade =
          await registry.install(manifestJson(versionCode: 3));

      expect(downgrade.ok, isFalse);
      expect(downgrade.message, contains('更高'));
    });

    test('同版本或更高版本可以覆盖安装', () async {
      await registry.install(manifestJson(versionCode: 5, name: '旧名字'));
      final SourceInstallResult upgrade =
          await registry.install(manifestJson(versionCode: 6, name: '新名字'));

      expect(upgrade.ok, isTrue);
      expect(registry.entryOf('test.src')!.name, '新名字');
      expect(registry.entryOf('test.src')!.record.origin, SourceOrigin.file);
    });

    test('未知编码被拒', () async {
      final SourceInstallResult result =
          await registry.install(manifestJson(charset: 'klingon'));
      expect(result.ok, isFalse);
      expect(result.message, contains('编码'));
    });

    test('自动机编码 auto 被接受', () async {
      final SourceInstallResult result = await registry.install(manifestJson(charset: 'auto'));
      expect(result.ok, isTrue);
    });
  });

  group('启用状态', () {
    test('停用后不再提供引擎，但仍列在表里', () async {
      await registry.install(manifestJson());
      await registry.setEnabled('test.src', false);

      final SourceEntry entry = registry.entryOf('test.src')!;
      expect(entry.status, SourceStatus.disabled);
      expect(registry.engineFor('test.src'), isNull);
      expect(registry.usableEntries, isEmpty);
    });

    test('重新启用可以恢复', () async {
      await registry.install(manifestJson());
      await registry.setEnabled('test.src', false);
      await registry.setEnabled('test.src', true);
      expect(registry.entryOf('test.src')!.status, SourceStatus.ready);
    });

    test('卸载后从表里消失', () async {
      await registry.install(manifestJson());
      await registry.remove('test.src');
      expect(registry.entryOf('test.src'), isNull);
      expect(await dao.findAll(), isEmpty);
    });
  });

  group('运行期错误留痕', () {
    test('markError 记录原因并把状态标为 error', () async {
      await registry.install(manifestJson());
      await registry.markError('test.src', '选择器已失效');

      final SourceEntry entry = registry.entryOf('test.src')!;
      expect(entry.status, SourceStatus.error);
      expect(entry.error, '选择器已失效');
    });

    test('错误信息跨重启保留（重新 load 后仍可见）', () async {
      await registry.install(manifestJson());
      await registry.markError('test.src', '网络不通');

      final SourceRegistry reloaded = SourceRegistry(dao: dao, fetcher: fetcher);
      await reloaded.load();
      expect(reloaded.entryOf('test.src')!.error, '网络不通');
      await reloaded.dispose();
    });

    test('加载期声明损坏的源被标成 error 而不是让整表加载失败', () async {
      await dao.upsert(const SourceRecord(
        id: 'broken.src',
        name: '坏源',
        manifestJson: '{ 不是 JSON',
        installedAt: 1,
        updatedAt: 1,
      ));
      await registry.install(manifestJson());

      await registry.load();
      expect(registry.entryOf('broken.src')!.status, SourceStatus.error);
      expect(registry.entryOf('broken.src')!.error, contains('声明解析失败'));
      expect(registry.usableEntries.length, 1, reason: '一个坏源不应拖垮其它源');
    });
  });

  group('声明变更订阅', () {
    test('安装/启停/卸载都会发出变更通知', () async {
      int notifications = 0;
      registry.changes.listen((_) => notifications++);

      await registry.install(manifestJson());
      await registry.setEnabled('test.src', false);
      await registry.remove('test.src');
      await Future<void>.delayed(Duration.zero);

      expect(notifications, greaterThanOrEqualTo(3));
    });
  });

  group('引擎可用性', () {
    test('注册表产出的引擎能真正抓取（走 fake 传输）', () async {
      await registry.install(manifestJson());
      fetcher.route(
        '/read/2001',
        '<html><body><div id="content"><p>第一段</p><p>第二段</p></div></body></html>',
      );

      final SourceEngine engine = registry.engineFor('test.src')!;
      final content = await engine.chapterContent('2001');

      expect(content.blocks.map((dynamic b) => b.text as String).toList(), <String>['第一段', '第二段']);
    });

    test('engineFor 拿不到源时由上层给出可读原因', () async {
      await registry.install(manifestJson());
      await registry.setEnabled('test.src', false);
      expect(registry.engineFor('test.src'), isNull);
      expect(registry.entryOf('test.src')!.status, SourceStatus.disabled);
    });
  });
}
