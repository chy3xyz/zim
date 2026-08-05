import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub OAuth client for mobile apps
/// Only handles authorization code flow, token exchange is done on server
class GitHubOAuthClient {
  final String clientId;
  final String redirectUri;
  final String customScheme;
  final List<String> scopes;
  final String serverTokenEndpoint; // Server endpoint to exchange code for token

  GitHubOAuthClient({
    required this.clientId,
    required this.redirectUri,
    required this.customScheme,
    required this.serverTokenEndpoint,
    this.scopes = const ['user:email', 'read:user'],
  });

  /// Get authorization code from GitHub
  Future<String?> getAuthorizationCode() async {
    try {
      // Generate PKCE parameters for security
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);
      final state = _generateState();

      // Build authorization URL
      final authUrl = _buildAuthorizationUrl(
        codeChallenge: codeChallenge,
        state: state,
      );

      // Launch web auth
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: customScheme,
      );

      // Extract authorization code from callback
      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];

      if (code != null) {
        // Store code verifier for server exchange
        await _storeCodeVerifier(codeVerifier);
        return code;
      }

      return null;
    } catch (e) {
      debugPrint('GitHub OAuth error: $e');
      return null;
    }
  }

  Future<({String state, bool isRegister})?> getState() async {
    try {
      final authUrl = await _queryRedirectUri();
      // Launch web auth
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: customScheme,
      );

      // Extract authorization code from callback
      final uri = Uri.parse(result);
      final code = uri.queryParameters['oauth_state'];
      final isRegister = uri.queryParameters['oauth_registered'];

      if (code != null) {
        return (state: code, isRegister: isRegister == 'true');
      }

      return null;
    } catch (e) {
      debugPrint('GitHub OAuth error: $e');
      return null;
    }
  }

  /// Exchange authorization code for access token via server
  Future<Map<String, dynamic>?> exchangeCodeForToken(String authCode) async {
    try {
      final codeVerifier = await _getStoredCodeVerifier();
      if (codeVerifier == null) {
        throw Exception('Code verifier not found');
      }

      final response = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'provider': 'github',
          'code': authCode,
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
        }),
      );

      if (response.statusCode == 200) {
        final tokenData = jsonDecode(response.body);

        // Store token data
        await _storeTokenData(tokenData);

        // Clear code verifier
        await _clearCodeVerifier();

        return tokenData;
      } else {
        throw Exception('Token exchange failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('Token exchange error: $e');
      return null;
    }
  }

  /// Get stored access token
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('github_access_token');
  }

  /// Check if access token is valid
  Future<bool> isTokenValid() async {
    final token = await getAccessToken();
    if (token == null) return false;

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get user info from GitHub API
  Future<Map<String, dynamic>?> getUserInfo() async {
    final token = await getAccessToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      debugPrint('Get user info error: $e');
      return null;
    }
  }

  /// Logout and clear stored tokens
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('github_access_token');
    await prefs.remove('github_refresh_token');
    await prefs.remove('github_token_expires_at');
    await _clearCodeVerifier();
  }

  /// Query redirect uri
  Future<String> _queryRedirectUri() async {
    final dio = Dio();

    try {
      final response = await dio.get(
        '$serverTokenEndpoint/oauth/login/github?cb=io.github.login://oauth/callback',
        options: Options(
          followRedirects: false, // 禁止自动跟随重定向
          validateStatus: (status) => status != null && status < 400, // 接受 3xx
        ),
      );

      if (response.isRedirect == true ||
          (response.statusCode != null && response.statusCode! >= 300 && response.statusCode! < 400)) {
        final location = response.headers.value('location');
        print('Redirect to: $location');

        return location ?? '';
      } else {
        print('Response status: ${response.statusCode}');
      }
    } catch (e) {
      print('Request failed: $e');
    }

    return '';
  }

  /// Build authorization URL
  String _buildAuthorizationUrl({
    required String codeChallenge,
    required String state,
  }) {
    final params = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scopes.join(' '),
      'state': state,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'response_type': 'code',
    };

    final query = params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');

    return 'https://github.com/login/oauth/authorize?$query';
  }

  /// Generate PKCE code verifier
  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Generate PKCE code challenge
  String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generate state parameter
  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Store code verifier
  Future<void> _storeCodeVerifier(String codeVerifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_code_verifier', codeVerifier);
  }

  /// Get stored code verifier
  Future<String?> _getStoredCodeVerifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('github_code_verifier');
  }

  /// Clear code verifier
  Future<void> _clearCodeVerifier() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('github_code_verifier');
  }

  /// Store token data
  Future<void> _storeTokenData(Map<String, dynamic> tokenData) async {
    final prefs = await SharedPreferences.getInstance();

    if (tokenData['access_token'] != null) {
      await prefs.setString('github_access_token', tokenData['access_token']);
    }

    if (tokenData['refresh_token'] != null) {
      await prefs.setString('github_refresh_token', tokenData['refresh_token']);
    }

    if (tokenData['expires_in'] != null) {
      final expiresAt = DateTime.now().add(
        Duration(seconds: tokenData['expires_in']),
      );
      await prefs.setString('github_token_expires_at', expiresAt.toIso8601String());
    }
  }
}
