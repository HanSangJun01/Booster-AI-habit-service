import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'session.dart';

/// API 요청 실패 시 던지는 예외.
///
/// [statusCode]가 null이면 요청이 서버에 닿지 못한 것(연결 실패/타임아웃)이고,
/// 값이 있으면 서버가 응답한 에러다. [errorCode]는 백엔드 에러 엔벨로프의
/// `errorCode` 필드로, 화면이 사유별로 다르게 반응해야 할 때 쓴다
/// (예: INSUFFICIENT_COIN, CHALLENGE_FULL, UNAUTHORIZED).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;

  ApiException(this.message, {this.statusCode, this.errorCode});

  /// 인증 만료/누락. 로그인 화면으로 돌려보내야 하는 상황.
  bool get isUnauthorized => statusCode == 401 || errorCode == 'UNAUTHORIZED';

  @override
  String toString() => message;
}

/// 백엔드 API 공통 클라이언트 (`integration/a-b-axis` 기준).
///
/// ## 응답 형태가 두 가지다
/// 백엔드는 성공 응답의 모양이 컨트롤러 계열마다 다르다:
/// - B축(Challenge/CheckIn/Participant/Team/Social/Settlement): `ApiResponse<T>`
///   엔벨로프 → `{"success": true, "message": ..., "data": ...}`
/// - A축(Auth/User/PersonalCheckIn/PersonalLocation/Dashboard):
///   DTO를 그대로 반환 → `{"userId": 1, ...}` 처럼 엔벨로프가 없다.
///
/// 에러는 양쪽 모두 `GlobalExceptionHandler`가 단일 규약으로 변환한다:
/// `{"success": false, "message": ..., "errorCode": ...}`.
///
/// 그래서 성공 판정을 `success == true`로만 하면 A축 엔드포인트(로그인 포함)가
/// 전부 실패한다. 아래 [_unwrap]이 두 형태를 모두 받아낸다.
class ApiClient {
  /// `--dart-define=API_BASE_URL=...`로 덮어쓸 수 있다. 빈 문자열이면
  /// 안 넘긴 것으로 보고 [_platformDefaultBaseUrl]로 내려간다.
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// 개발 중 붙을 호스트 주소는 플랫폼마다 다르다.
  ///
  /// 안드로이드 에뮬레이터는 자기 자신을 localhost로 가지기 때문에
  /// 호스트 PC를 가리키려면 10.0.2.2를 써야 한다. 반면 iOS 시뮬레이터는
  /// 맥과 네트워크를 그대로 공유해서 localhost가 곧바로 호스트다 — 거기서
  /// 10.0.2.2를 부르면 아무데도 닿지 않는다.
  ///
  /// 실기기는 어느 쪽도 아니다. 홈 PC의 LAN IP를
  /// `--dart-define=API_BASE_URL=http://192.168.x.x:8080/api`로 넣어줘야 한다.
  static String get _platformDefaultBaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api';
    }
    return 'http://localhost:8080/api';
  }

  static String get _defaultBaseUrl =>
      _envBaseUrl.isNotEmpty ? _envBaseUrl : _platformDefaultBaseUrl;

  static String? _baseUrlOverride;

  /// 실제로 요청이 나가는 주소.
  static String get baseUrl => _baseUrlOverride ?? _defaultBaseUrl;

  /// 테스트가 띄운 임시 서버로 요청을 돌리기 위한 통로.
  ///
  /// 테스트 서버는 포트 충돌을 피하려고 빈 포트를 받아 뜨기 때문에 주소가
  /// 매번 달라진다. `--dart-define`은 컴파일 타임이라 그걸 가리킬 수 없다.
  /// null을 넘기면 원래 값으로 돌아간다.
  @visibleForTesting
  static void overrideBaseUrl(String? value) => _baseUrlOverride = value;

  /// 응답 대기 상한. 인증 바텀시트처럼 요청이 끝날 때까지 닫히지 않는 화면이
  /// 있어서, 상한이 없으면 응답 없는 서버에 화면이 영영 묶인다.
  static const Duration _timeout = Duration(seconds: 15);

  /// 사진 업로드용 상한. 본문 전송에 더해 서버가 AI 판정을 기다렸다 답한다.
  static const Duration _uploadTimeout = Duration(seconds: 60);

  /// 토큰 만료·누락으로 401을 받았을 때 호출된다(`main.dart`에서 연결).
  ///
  /// 화면마다 401을 따로 처리하게 두면 실수로 빠뜨린 화면에서 사용자가 갇힌다
  /// — 에러 토스트만 반복되고 로그인으로 돌아갈 길이 없다. 그래서 여기서 한 번
  /// 잡아 전역으로 넘긴다.
  static void Function()? onUnauthorized;

  /// 응답 본문을 객체로 받는다. 형식이 다르면 [ApiException]으로 바꿔 던진다.
  ///
  /// `as Map<String, dynamic>`으로 직접 캐스팅하면 계약이 어긋났을 때 화면의
  /// `on ApiException` 핸들러를 그냥 지나쳐서 로딩 스피너가 영영 돌아버린다
  /// (코인 내역 화면이 실제로 그랬다). 여기서 타입을 바꿔주면 화면은 이미
  /// 가지고 있는 에러 처리로 그대로 받아낼 수 있다.
  static Map<String, dynamic> asObject(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    throw ApiException('서버 응답 형식이 예상과 달라요. 잠시 후 다시 시도해주세요');
  }

  /// 업로드 상한. 서버가 10MB를 넘기면 413으로 끊는데, 그건 파일을 다 올려보낸
  /// 뒤에 오는 답이다. 데이터와 시간을 버리기 전에 앱이 먼저 잘라낸다.
  static const int maxUploadBytes = 10 * 1024 * 1024;

  /// 서버가 받아주는 이미지 형식. 그 외는 415다.
  static const Set<String> allowedImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  static Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);
  static Future<dynamic> post(String path, {Object? body}) => _send('POST', path, body: body);
  static Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);
  static Future<dynamic> delete(String path) => _send('DELETE', path);

  /// 이미지 한 장을 `multipart/form-data`로 올린다.
  ///
  /// AI 사진 인증이 유일한 사용처다. [fields]에는 `category`처럼 파일과 함께
  /// 가야 하는 문자열을 넣는다.
  ///
  /// 타임아웃이 [_timeout]보다 길다 — 업로드는 요청 본문 전송 자체에 시간이
  /// 걸리는 데다, 서버가 AI 서비스 응답까지 기다린 뒤에 답한다. 15초로 끊으면
  /// 멀쩡히 처리되는 중인 인증을 앱이 먼저 포기한다.
  static Future<dynamic> postImage(
    String path, {
    required String filePath,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) async {
    final extension = filePath.split('.').last.toLowerCase();
    if (!allowedImageExtensions.contains(extension)) {
      throw ApiException('JPG·PNG·WEBP 이미지만 올릴 수 있어요');
    }
    if (bytes.length > maxUploadBytes) {
      throw ApiException('사진이 너무 커요. 10MB 이하로 올려주세요');
    }

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(_headers())
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: 'verification.$extension',
        contentType: MediaType('image', extension == 'jpg' ? 'jpeg' : extension),
      ));

    late http.Response res;
    try {
      final streamed = await request.send().timeout(_uploadTimeout);
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException('사진 전송이 너무 오래 걸려요. 잠시 후 다시 시도해주세요');
    } catch (_) {
      throw ApiException('서버에 연결할 수 없습니다');
    }

    return _unwrap(res, path);
  }

  /// 공통 헤더. 로그인 후 Session에 저장된 accessToken을 Bearer로 실어 보낸다.
  /// 백엔드는 `/api/auth/**`를 제외한 모든 경로에 인증을 요구하고
  /// (`SecurityConfig`), JWT의 subject를 userId로 해석한다 — 그래서 앱이
  /// 요청 바디에 userId를 따로 넣을 필요가 없다.
  static Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{'Accept': 'application/json'};
    if (jsonBody) headers['Content-Type'] = 'application/json; charset=utf-8';
    final token = Session.accessToken;
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        for (final e in query.entries)
          if (e.value != null) e.key: '${e.value}',
      });
    }

    // 인코딩은 try 밖에서 한다 — 안에서 실패하면 앱 쪽 버그(직렬화 불가능한 값)가
    // "서버에 연결할 수 없습니다"로 둔갑해서 서버를 붙잡고 헤매게 된다.
    final String? encoded = body == null ? null : jsonEncode(body);

    late http.Response res;
    try {
      final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = http.get(uri, headers: _headers());
          break;
        case 'POST':
          request = http.post(uri, headers: _headers(jsonBody: true), body: encoded);
          break;
        case 'PUT':
          request = http.put(uri, headers: _headers(jsonBody: true), body: encoded);
          break;
        case 'DELETE':
          request = http.delete(uri, headers: _headers());
          break;
        default:
          throw ApiException('지원하지 않는 요청 방식입니다');
      }
      res = await request.timeout(_timeout);
    } on ApiException {
      // 위 default 분기 — 연결 실패로 뭉뚱그리지 않고 그대로 올린다.
      rethrow;
    } on TimeoutException {
      // 서버에 닿긴 했는데 제때 답이 없는 경우. "연결할 수 없다"와 원인이 달라서
      // (서버 과부하 vs 주소·방화벽 문제) 구분해줘야 사용자가 헛다리를 안 짚는다.
      throw ApiException('서버 응답이 너무 늦어요. 잠시 후 다시 시도해주세요');
    } catch (_) {
      throw ApiException('서버에 연결할 수 없습니다');
    }

    return _unwrap(res, path);
  }

  static dynamic _unwrap(http.Response res, String path) {
    dynamic decoded;
    try {
      // res.body는 Content-Type에 charset이 없으면 latin1로 디코딩해서 한글이
      // 깨진다. 백엔드는 charset을 안 붙이므로 bodyBytes를 직접 UTF-8로 읽는다.
      if (res.bodyBytes.isNotEmpty) decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      // JSON이 아닌 응답(프록시 에러 페이지 등) — 아래에서 상태 코드로 처리.
    }

    // 에러 엔벨로프이거나 B축 성공 엔벨로프인 경우.
    final isEnvelope = decoded is Map<String, dynamic> && decoded.containsKey('success');
    final success = res.statusCode >= 200 && res.statusCode < 300;

    if (isEnvelope) {
      final envelope = decoded;
      if (success && envelope['success'] == true) return envelope['data'];
      _fail(
        ApiException(
          (envelope['message'] as String?) ?? _messageFor(res.statusCode),
          statusCode: res.statusCode,
          errorCode: envelope['errorCode'] as String?,
        ),
        path,
      );
    }

    // A축 컨트롤러의 생 DTO 응답. 204 No Content면 decoded가 null이다.
    if (success) return decoded;

    _fail(
      ApiException(_koreanMessage(decoded) ?? _messageFor(res.statusCode),
          statusCode: res.statusCode),
      path,
    );
  }

  /// 엔벨로프가 아닌 에러 본문에서 사용자에게 보여줄 만한 문구를 꺼낸다.
  ///
  /// 백엔드 `GlobalExceptionHandler`를 타면 항상 `success` 키가 붙지만, 그걸
  /// 거치지 않는 응답(스프링 기본 검증 오류 등)은 `message`만 들고 온다. 그걸
  /// 버리면 "요청 처리 중 오류가 발생했습니다"만 남아서 사용자가 어느 칸을
  /// 고쳐야 하는지 알 수 없다.
  ///
  /// 한글이 들어 있을 때만 쓴다 — 스프링 기본 문구(`No message available`,
  /// `Validation failed for object...`)를 그대로 띄우면 안내가 아니라 잡음이다.
  static String? _koreanMessage(dynamic decoded) {
    if (decoded is! Map) return null;
    final message = decoded['message'];
    if (message is! String) return null;
    final trimmed = message.trim();
    if (trimmed.isEmpty || !RegExp(r'[가-힣]').hasMatch(trimmed)) return null;
    return trimmed;
  }

  /// 예외를 던지기 전에 전역 처리가 필요한지 판단한다.
  ///
  /// `/auth/**`의 401은 "비밀번호가 틀렸다"는 뜻이라 로그인 화면이 직접 보여줘야
  /// 한다. 그 외 경로의 401만 토큰 만료로 보고 [onUnauthorized]로 넘긴다 —
  /// 안 그러면 로그인 실패가 곧바로 로그인 화면 재진입을 부른다.
  static Never _fail(ApiException e, String path) {
    if (e.isUnauthorized && !path.startsWith('/auth')) onUnauthorized?.call();
    throw e;
  }

  /// 서버가 메시지를 안 줬을 때(에러 페이지·프록시 응답 등) 상태 코드로 만드는
  /// 대체 문구. 전부 "오류가 발생했습니다"로 뭉치면 원인 추적이 불가능하다.
  static String _messageFor(int statusCode) {
    if (statusCode == 401) return '로그인이 필요합니다';
    if (statusCode == 403) return '권한이 없습니다';
    if (statusCode == 404) return '요청한 정보를 찾을 수 없습니다';
    if (statusCode >= 500) return '서버에 문제가 발생했어요. 잠시 후 다시 시도해주세요';
    return '요청 처리 중 오류가 발생했습니다';
  }
}
