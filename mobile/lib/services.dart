// lib/services.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

class AuthService {
  // Singleton pattern is pragmatic for simple auth state.
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _sessionId;

  // Fail fast if config is missing.
  String get baseUrl {
    final url = dotenv.env['API_URL'];
    if (url == null) throw Exception("API_URL not configured in .env");
    return url;
  }

  Future<Map<String, String>> beginLoginFlow() async {
    // 1. Fetch Login URL. Explicitly request 'mobile' flow.
    final loginEndpoint = Uri.parse('$baseUrl/auth/login?platform=mobile');
    final loginRes = await http.get(loginEndpoint);

    if (loginRes.statusCode != 200) {
      throw Exception('Failed to get login URL: ${loginRes.statusCode}');
    }

    final authUrl = jsonDecode(loginRes.body)['url'];

    // 2. Browser Flow.
    final callbackResult = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: 'project-dupes',
    );

    // 3. Extract Handoff Code.
    final code = Uri.parse(callbackResult).queryParameters['handoff_code'];
    if (code == null) {
      throw Exception("Authentication callback missing handoff_code");
    }

    // 4. Exchange for Session.
    final exchangeRes = await http.post(
      Uri.parse('$baseUrl/auth/exchange'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'handoff_code': code}),
    );

    if (exchangeRes.statusCode != 200) {
      throw Exception('Session exchange failed: ${exchangeRes.body}');
    }

    final data = jsonDecode(exchangeRes.body);

    // Store session state.
    _sessionId = data['session_id'];

    return {'code': code, 'email': data['email'] ?? 'Unknown'};
  }

  Future<void> logout() async {}
}
