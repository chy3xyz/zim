import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:oauth2_client/github_oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'oauth_service.dart';
import '../models/auth_result.dart';

/// GitHub OAuth service configuration
class GitHubOAuthConfig extends OAuthServiceConfig {
  final String customScheme;

  GitHubOAuthConfig({
    required super.clientId,
    required super.redirectUri,
    required this.customScheme,
    super.clientSecret,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? tokenEndpoint,
    String? userInfoEndpoint,
    super.revocationEndpoint,
    bool? usePkce,
    Map<String, String>? additionalParameters,
  }) : super(
          providerName: 'github',
          scopes: scopes ?? const ['user:email', 'read:user'],
          authorizationEndpoint: authorizationEndpoint ?? 'https://github.com/login/oauth/authorize',
          tokenEndpoint: tokenEndpoint ?? 'https://github.com/login/oauth/access_token',
          userInfoEndpoint: userInfoEndpoint ?? 'https://api.github.com/user',
          usePkce: usePkce ?? false, // GitHub doesn't require PKCE
          additionalParameters: additionalParameters ?? const {},
        );
}

/// GitHub OAuth service implementation based on oauth2_client
class GitHubOAuth2ClientService implements OAuthService {
  late final GitHubOAuth2Client _client;
  late final OAuth2Helper _helper;
  late final GitHubOAuthConfig _config;

  // Cache keys
  static const String _cacheKeyPrefix = 'github_oauth2_client_';
  static const String _userInfoKey = '${_cacheKeyPrefix}user_info';

  GitHubOAuth2ClientService({required GitHubOAuthConfig config}) {
    _config = config;

    _client = GitHubOAuth2Client(
      redirectUri: _config.redirectUri,
      customUriScheme: _config.customScheme,
    );

    _helper = OAuth2Helper(
      _client,
      grantType: OAuth2Helper.authorizationCode,
      clientId: _config.clientId,
      clientSecret: _config.clientSecret,
      scopes: _config.scopes,
    );
  }

  /// Get current configuration
  GitHubOAuthConfig get config => _config;

  @override
  String get providerName => _config.providerName;

  @override
  String get displayName => 'GitHub';

  @override
  bool get supportsSilentSignIn => true;

  @override
  bool get supportsTokenRefresh => false; // GitHub doesn't support token refresh

  @override
  Future<AuthResult?> signIn() async {
    try {
      debugPrint('GitHub OAuth2Client: Starting sign in...');

      // Use oauth2_client for authorization
      final tokenResponse = await _client.getTokenWithAuthCodeFlow(
        clientId: _config.clientId,
        clientSecret: _config.clientSecret,
        scopes: _config.scopes,
      );

      if (tokenResponse.accessToken == null) {
        debugPrint('GitHub OAuth2Client: No access token received');
        return AuthResult.cancelled(providerName);
      }

      debugPrint('GitHub OAuth2Client: Access token received');

      // Get user information
      final userInfo = await _fetchUserInfo(tokenResponse.accessToken!);
      if (userInfo == null) {
        debugPrint('GitHub OAuth2Client: Failed to fetch user info');
        return AuthResult.failure(
          provider: providerName,
          error: 'Failed to fetch user information',
        );
      }

      // Cache user information
      await _cacheUserInfo(userInfo);

      return AuthResult.success(
        provider: providerName,
        userId: userInfo['id']?.toString(),
        displayName: userInfo['name'] ?? userInfo['login'],
        email: userInfo['email'],
        photoUrl: userInfo['avatar_url'],
        accessToken: tokenResponse.accessToken,
        refreshToken: tokenResponse.refreshToken,
        idToken: null,
        expiresAt: tokenResponse.expirationDate,
      );
    } catch (e) {
      debugPrint('GitHub OAuth2Client sign-in failed: $e');
      if (e.toString().contains('User cancelled') || e.toString().contains('User denied')) {
        return AuthResult.cancelled(providerName);
      }
      return AuthResult.failure(
        provider: providerName,
        error: 'GitHub sign-in failed: $e',
      );
    }
  }

  @override
  Future<bool> isSignedIn() async {
    try {
      final token = await _helper.getToken();
      return token != null && !token.isExpired();
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Error checking sign in status: $e');
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _helper.disconnect();
      await clearCache();
      debugPrint('GitHub OAuth2Client: Sign out successful');
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Sign out error: $e');
      await clearCache();
    }
  }

  @override
  Future<AuthResult?> silentSignIn() async {
    try {
      debugPrint('GitHub OAuth2Client: Attempting silent sign in...');

      final token = await _helper.getToken();
      if (token == null || token.isExpired()) {
        debugPrint('GitHub OAuth2Client: No valid token available');
        return null;
      }

      // Get cached user information
      final prefs = await SharedPreferences.getInstance();
      final userInfoString = prefs.getString(_userInfoKey);

      Map<String, dynamic>? userInfo;
      if (userInfoString != null) {
        userInfo = json.decode(userInfoString);
      } else {
        // If no cached user information, fetch it again
        userInfo = await _fetchUserInfo(token.accessToken!);
        if (userInfo != null) {
          await _cacheUserInfo(userInfo);
        }
      }

      if (userInfo == null) {
        debugPrint('GitHub OAuth2Client: Failed to get user info');
        return null;
      }

      debugPrint('GitHub OAuth2Client: Silent sign in successful');
      return AuthResult.success(
        provider: providerName,
        userId: userInfo['id']?.toString(),
        displayName: userInfo['name'] ?? userInfo['login'],
        email: userInfo['email'],
        photoUrl: userInfo['avatar_url'],
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
        idToken: null,
        expiresAt: token.expirationDate,
      );
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Silent sign in failed: $e');
      return null;
    }
  }

  @override
  Future<AuthResult?> refreshToken() async {
    // GitHub doesn't support token refresh
    return null;
  }

  @override
  Future<AuthResult?> getCurrentUser() async {
    return await silentSignIn();
  }

  @override
  Future<bool> revokeToken() async {
    // GitHub doesn't provide standard token revocation endpoint
    // Just disconnect and clear cache
    try {
      await _helper.disconnect();
      await clearCache();
      return true;
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Token revocation failed: $e');
      return false;
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userInfoKey);
      debugPrint('GitHub OAuth2Client: Cache cleared');
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Clear cache error: $e');
    }
  }

  @override
  Future<bool> validateToken() async {
    try {
      final token = await _helper.getToken();
      if (token == null || token.isExpired()) {
        return false;
      }

      // Try to use token to get user information for validation
      final userInfo = await _fetchUserInfo(token.accessToken!);
      return userInfo != null;
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Token validation failed: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getGrantedScopes() async {
    return _config.scopes;
  }

  @override
  Future<bool> hasScope(String scope) async {
    final grantedScopes = await getGrantedScopes();
    return grantedScopes.contains(scope);
  }

  @override
  Future<AuthResult?> requestAdditionalScopes(List<String> scopes) async {
    // GitHub OAuth2Client doesn't support requesting additional scopes directly
    // Need to re-authenticate with new scopes
    return null;
  }

  /// Get user information
  Future<Map<String, dynamic>?> _fetchUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(_config.userInfoEndpoint!),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/vnd.github.v3+json',
        },
      );

      if (response.statusCode == 200) {
        final userInfo = json.decode(response.body);
        debugPrint('GitHub OAuth2Client: User info fetched successfully');
        return userInfo;
      } else {
        debugPrint('GitHub OAuth2Client: Failed to fetch user info: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Error fetching user info: $e');
      return null;
    }
  }

  /// Cache user information
  Future<void> _cacheUserInfo(Map<String, dynamic> userInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userInfoKey, json.encode(userInfo));
      debugPrint('GitHub OAuth2Client: User info cached');
    } catch (e) {
      debugPrint('GitHub OAuth2Client: Error caching user info: $e');
    }
  }
}
