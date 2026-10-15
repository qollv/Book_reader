import 'package:dio/dio.dart';

import 'package:novel_reader/core/import_exception.dart';
import 'package:novel_reader/services/sync/sync_service.dart';

/// 同步通道：把 SyncPayload 推送到对端、从对端拉取。
abstract class SyncTransport {
  Future<SyncPayload?> download();

  Future<void> upload(SyncPayload payload);
}

/// 对端响应体 → SyncPayload。非对象 JSON（数组/字符串/数字）抛可读异常，
/// 而不是把 TypeError 漏给 UI 层。
SyncPayload _payloadFromResponse(Object? data) {
  if (data is Map<String, Object?>) {
    return SyncPayload.fromJson(data);
  }
  throw const ImportException('同步数据格式不正确：对端返回了非对象数据');
}

/// 局域网同步：对端是另一台跑着本 App 的设备（LanTransferServer）。
class LanSyncTransport implements SyncTransport {
  LanSyncTransport({required String peerBaseUrl, required String token, Dio? dio})
      : _peerBaseUrl = peerBaseUrl.endsWith('/') ? peerBaseUrl : '$peerBaseUrl/',
        _token = token,
        _dio = dio ?? Dio();

  final String _peerBaseUrl;
  final String _token;
  final Dio _dio;

  Map<String, String> get _headers => <String, String>{'x-token': _token};

  @override
  Future<SyncPayload?> download() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '${_peerBaseUrl}sync',
        options: Options(headers: _headers),
      );
      if (response.statusCode == 404 || response.data == null) {
        return null;
      }
      return _payloadFromResponse(response.data);
    } on DioException catch (error) {
      // 对端尚无同步数据是首同步的正常场景，返回 null 而非抛异常
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> upload(SyncPayload payload) async {
    await _dio.post<dynamic>(
      '${_peerBaseUrl}sync',
      data: payload.toJson(),
      options: Options(headers: _headers),
    );
  }
}

/// 云端同步：用户自建服务端，apiToken 由用户填写后经上层持久化，
/// 不硬编码在程序里。
class CloudSyncTransport implements SyncTransport {
  CloudSyncTransport({required String baseUrl, required String apiToken, Dio? dio})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        _apiToken = apiToken,
        _dio = dio ?? Dio();

  final String _baseUrl;
  final String _apiToken;
  final Dio _dio;

  @override
  Future<SyncPayload?> download() async {
    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        '${_baseUrl}sync',
        options: Options(headers: <String, String>{'authorization': 'Bearer $_apiToken'}),
      );
      if (response.statusCode == 404 || response.data == null) {
        return null;
      }
      return _payloadFromResponse(response.data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<void> upload(SyncPayload payload) async {
    await _dio.post<dynamic>(
      '${_baseUrl}sync',
      data: payload.toJson(),
      options: Options(headers: <String, String>{'authorization': 'Bearer $_apiToken'}),
    );
  }
}
