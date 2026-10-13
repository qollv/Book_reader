import 'package:dio/dio.dart';

import 'package:novel_reader/services/sync/sync_service.dart';

/// 同步通道：把 SyncPayload 推送到对端、从对端拉取。
abstract class SyncTransport {
  Future<SyncPayload?> download();

  Future<void> upload(SyncPayload payload);
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
    final Response<dynamic> response = await _dio.get<dynamic>(
      '${_peerBaseUrl}sync',
      options: Options(headers: _headers),
    );
    if (response.statusCode == 404 || response.data == null) {
      return null;
    }
    return SyncPayload.fromJson(response.data as Map<String, Object?>);
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
    final Response<dynamic> response = await _dio.get<dynamic>(
      '${_baseUrl}sync',
      options: Options(headers: <String, String>{'authorization': 'Bearer $_apiToken'}),
    );
    if (response.statusCode == 404 || response.data == null) {
      return null;
    }
    return SyncPayload.fromJson(response.data as Map<String, Object?>);
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
