import 'dart:convert';
import 'package:http/http.dart' as http;

/// API 요청 실패 시 던지는 예외. `message`는 서버 응답의 `message` 필드
/// (docs/api/MVP_API_SPEC.md §2.3 공통 에러 포맷) 또는 네트워크 오류 설명.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// 백엔드 API 공통 클라이언트.
///
/// baseUrl은 `--dart-define=API_BASE_URL=...`로 실행 시 덮어쓸 수 있다.
/// 기본값은 안드로이드 에뮬레이터에서 호스트 PC의 localhost:8080을 가리키는
/// 주소이며, 백엔드 서버 주소/포트가 정해지면 이 기본값만 바꾸면 된다.
class ApiClient {
  static const String baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080/api');

  static Future<dynamic> get(String path) => _send('GET', path);
  static Future<dynamic> post(String path, {Map<String, dynamic>? body}) =>
      _send('POST', path, body: body);
  static Future<dynamic> patch(String path, {Map<String, dynamic>? body}) =>
      _send('PATCH', path, body: body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  static Future<dynamic> _send(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await http.get(uri);
          break;
        case 'POST':
          res = await http.post(uri,
              headers: {'Content-Type': 'application/json'},
              body: body != null ? jsonEncode(body) : null);
          break;
        case 'PATCH':
          res = await http.patch(uri,
              headers: {'Content-Type': 'application/json'},
              body: body != null ? jsonEncode(body) : null);
          break;
        case 'DELETE':
          res = await http.delete(uri);
          break;
        default:
          throw ApiException('지원하지 않는 요청 방식입니다');
      }
    } catch (_) {
      throw ApiException('서버에 연결할 수 없습니다');
    }

    Map<String, dynamic>? parsed;
    try {
      if (res.body.isNotEmpty) parsed = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      // 서버가 JSON이 아닌 응답을 준 경우, 아래에서 상태 코드 기준으로 처리한다.
    }

    final success = parsed?['success'] == true;
    if (res.statusCode >= 200 && res.statusCode < 300 && success) {
      return parsed?['data'];
    }
    throw ApiException(
      (parsed?['message'] as String?) ?? '요청 처리 중 오류가 발생했습니다',
      statusCode: res.statusCode,
    );
  }
}
