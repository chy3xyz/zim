import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'oauth_service.dart';
import '../models/auth_result.dart';

/// Google OAuth service configuration
class GoogleOAuthConfig extends OAuthServiceConfig {
  GoogleOAuthConfig({
    required super.clientId,
    required super.redirectUri,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? tokenEndpoint,
    String? userInfoEndpoint,
    String? revocationEndpoint,
    bool? usePkce,
    Map<String, String>? additionalParameters,
  }) : super(
          providerName: 'google',
          scopes: scopes ?? const ['openid', 'profile', 'email'],
          authorizationEndpoint: authorizationEndpoint ?? 'https://accounts.google.com/o/oauth2/v2/auth',
          tokenEndpoint: tokenEndpoint ?? 'https://oauth2.googleapis.com/token',
          userInfoEndpoint: userInfoEndpoint ?? 'https://www.googleapis.com/oauth2/v2/userinfo',
          revocationEndpoint: revocationEndpoint ?? 'https://oauth2.googleapis.com/revoke',
          usePkce: usePkce ?? true,
          additionalParameters: additionalParameters ??
              const {
                'access_type': 'offline',
              },
        );
}

/// Google OAuth authentication service implementation
class GoogleAuthService implements OAuthService {
  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  late final GoogleOAuthConfig _config;

  GoogleAuthService({required GoogleOAuthConfig config}) {
    _config = config;
  }

  // Cache keys
  static const String _cacheKeyPrefix = 'google_auth_';
  static const String _accessTokenKey = '${_cacheKeyPrefix}access_token';
  static const String _refreshTokenKey = '${_cacheKeyPrefix}refresh_token';
  static const String _idTokenKey = '${_cacheKeyPrefix}id_token';
  static const String _expiresAtKey = '${_cacheKeyPrefix}expires_at';
  static const String _userInfoKey = '${_cacheKeyPrefix}user_info';
  static const String _scopesKey = '${_cacheKeyPrefix}scopes';

  /// Get current configuration
  GoogleOAuthConfig get config => _config;

  @override
  String get providerName => _config.providerName;

  @override
  String get displayName => 'Google';

  @override
  bool get supportsSilentSignIn => true;

  @override
  bool get supportsTokenRefresh => true;

  @override
  Future<AuthResult?> signIn() async {
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _config.clientId,
          _config.redirectUri,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: _config.authorizationEndpoint,
            tokenEndpoint: _config.tokenEndpoint!,
          ),
          scopes: _config.scopes,
          additionalParameters: _config.additionalParameters,
        ),
      );

      if (result.accessToken == null) {
        return AuthResult.cancelled(providerName);
      }

      // Get user information
      final userInfo = await _fetchUserInfo(result.accessToken!);

      // Cache authentication information
      await _cacheAuthResult(result, userInfo);

      return AuthResult.success(
        provider: providerName,
        userId: userInfo?['id'],
        displayName: userInfo?['name'],
        email: userInfo?['email'],
        photoUrl: userInfo?['picture'],
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiresAt: result.accessTokenExpirationDateTime,
      );
    } catch (e) {
      debugPrint('GoogleAuthService signIn error: $e');

      // Handle user cancellation
      if (e.toString().contains('User cancelled') ||
          e.toString().contains('FlutterAppAuthUserCancelledException') ||
          e.toString().contains('WebAuthenticationSession Code=1') ||
          e.toString().contains('code: -3')) {
        debugPrint('GoogleAuthService: User cancelled sign in');
        return AuthResult.cancelled(providerName);
      }

      // Handle other authentication errors
      return AuthResult.failure(
        provider: providerName,
        error: 'Google sign-in failed: ${e.toString()}',
      );
    }
  }

  @override
  Future<bool> isSignedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      final expiresAtString = prefs.getString(_expiresAtKey);

      if (accessToken == null) return false;

      // Check if token has expired
      if (expiresAtString != null) {
        final expiresAt = DateTime.parse(expiresAtString);
        if (DateTime.now().isAfter(expiresAt)) {
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    await clearCache();
  }

  @override
  Future<AuthResult?> silentSignIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      final refreshToken = prefs.getString(_refreshTokenKey);
      final idToken = prefs.getString(_idTokenKey);
      final expiresAtString = prefs.getString(_expiresAtKey);
      final userInfoString = prefs.getString(_userInfoKey);

      if (accessToken == null) return null;

      DateTime? expiresAt;
      if (expiresAtString != null) {
        expiresAt = DateTime.parse(expiresAtString);
      }

      Map<String, dynamic>? userInfo;
      if (userInfoString != null) {
        userInfo = json.decode(userInfoString);
      }

      // Check if token has expired
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        // Try to refresh token
        return await this.refreshToken();
      }

      return AuthResult.success(
        provider: providerName,
        userId: userInfo?['id'],
        displayName: userInfo?['name'],
        email: userInfo?['email'],
        photoUrl: userInfo?['picture'],
        accessToken: accessToken,
        refreshToken: refreshToken,
        idToken: idToken,
        expiresAt: expiresAt,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<AuthResult?> refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_refreshTokenKey);

      if (refreshToken == null) return null;

      final TokenResponse result = await _appAuth.token(
        TokenRequest(
          _config.clientId,
          _config.redirectUri,
          refreshToken: refreshToken,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: _config.authorizationEndpoint,
            tokenEndpoint: _config.tokenEndpoint!,
          ),
        ),
      );

      if (result.accessToken == null) return null;

      // Get user information
      final userInfo = await _fetchUserInfo(result.accessToken!);

      // Update cache
      await _cacheTokenResponse(result, userInfo);

      return AuthResult.success(
        provider: providerName,
        userId: userInfo?['id'],
        displayName: userInfo?['name'],
        email: userInfo?['email'],
        photoUrl: userInfo?['picture'],
        accessToken: result.accessToken,
        refreshToken: result.refreshToken ?? refreshToken,
        idToken: result.idToken,
        expiresAt: result.accessTokenExpirationDateTime,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<AuthResult?> getCurrentUser() async {
    return await silentSignIn();
  }

  @override
  Future<bool> revokeToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);

      if (accessToken == null || _config.revocationEndpoint == null) return false;

      final response = await http.post(
        Uri.parse('${_config.revocationEndpoint}?token=$accessToken'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_idTokenKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_userInfoKey);
    await prefs.remove(_scopesKey);
  }

  @override
  Future<bool> validateToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);

      if (accessToken == null) return false;

      final response = await http.get(
        Uri.parse(_config.userInfoEndpoint!),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<String>> getGrantedScopes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scopesString = prefs.getString(_scopesKey);

      if (scopesString == null) return [];

      final scopesList = json.decode(scopesString) as List;
      return scopesList.cast<String>();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<bool> hasScope(String scope) async {
    final grantedScopes = await getGrantedScopes();
    return grantedScopes.contains(scope);
  }

  @override
  Future<AuthResult?> requestAdditionalScopes(List<String> scopes) async {
    try {
      final currentScopes = await getGrantedScopes();
      final allScopes = {...currentScopes, ...scopes}.toList();

      final AuthorizationTokenResponse result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          _config.clientId,
          _config.redirectUri,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: _config.authorizationEndpoint,
            tokenEndpoint: _config.tokenEndpoint!,
          ),
          scopes: allScopes,
          additionalParameters: {
            ..._config.additionalParameters,
          },
        ),
      );

      if (result.accessToken == null) {
        return AuthResult.cancelled(providerName);
      }

      // Get user information
      final userInfo = await _fetchUserInfo(result.accessToken!);

      // Update cache
      await _cacheAuthResult(result, userInfo);

      return AuthResult.success(
        provider: providerName,
        userId: userInfo?['id'],
        displayName: userInfo?['name'],
        email: userInfo?['email'],
        photoUrl: userInfo?['picture'],
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiresAt: result.accessTokenExpirationDateTime,
      );
    } catch (e) {
      return AuthResult.failure(
        provider: providerName,
        error: e.toString(),
      );
    }
  }

  /// Get user information
  Future<Map<String, dynamic>?> _fetchUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse(_config.userInfoEndpoint!),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Cache authentication result
  Future<void> _cacheAuthResult(AuthorizationTokenResponse result, Map<String, dynamic>? userInfo) async {
    final prefs = await SharedPreferences.getInstance();

    if (result.accessToken != null) {
      await prefs.setString(_accessTokenKey, result.accessToken!);
    }

    if (result.refreshToken != null) {
      await prefs.setString(_refreshTokenKey, result.refreshToken!);
    }

    if (result.idToken != null) {
      await prefs.setString(_idTokenKey, result.idToken!);
    }

    if (result.accessTokenExpirationDateTime != null) {
      await prefs.setString(_expiresAtKey, result.accessTokenExpirationDateTime!.toIso8601String());
    }

    if (userInfo != null) {
      await prefs.setString(_userInfoKey, json.encode(userInfo));
    }

    // Cache authorized permission scopes
    await prefs.setString(_scopesKey, json.encode(_config.scopes));
  }

  /// Cache token response
  Future<void> _cacheTokenResponse(TokenResponse result, Map<String, dynamic>? userInfo) async {
    final prefs = await SharedPreferences.getInstance();

    if (result.accessToken != null) {
      await prefs.setString(_accessTokenKey, result.accessToken!);
    }

    if (result.refreshToken != null) {
      await prefs.setString(_refreshTokenKey, result.refreshToken!);
    }

    if (result.idToken != null) {
      await prefs.setString(_idTokenKey, result.idToken!);
    }

    if (result.accessTokenExpirationDateTime != null) {
      await prefs.setString(_expiresAtKey, result.accessTokenExpirationDateTime!.toIso8601String());
    }

    if (userInfo != null) {
      await prefs.setString(_userInfoKey, json.encode(userInfo));
    }
  }
}
