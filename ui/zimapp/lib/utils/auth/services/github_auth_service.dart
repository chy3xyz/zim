import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'oauth_service.dart';
import '../models/auth_result.dart';
import 'github_oauth_client.dart';

/// GitHub OAuth service configuration
class GitHubOAuthConfig extends OAuthServiceConfig {
  /// Server token endpoint for secure token exchange
  final String serverTokenEndpoint;

  /// Custom scheme for OAuth callback
  final String customScheme;

  GitHubOAuthConfig({
    required super.clientId,
    required super.redirectUri,
    required this.serverTokenEndpoint,
    required this.customScheme,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? userInfoEndpoint,
    bool? usePkce,
  }) : super(
          providerName: 'github',
          scopes: scopes ?? const ['user:email', 'read:user'],
          authorizationEndpoint: authorizationEndpoint ?? 'https://github.com/login/oauth/authorize',
          userInfoEndpoint: userInfoEndpoint ?? 'https://api.github.com/user',
          usePkce: usePkce ?? false,
        );

  @override
  String toString() {
    return 'GitHubOAuthConfig(clientId: $clientId, serverTokenEndpoint: $serverTokenEndpoint, customScheme: $customScheme, scopes: $scopes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitHubOAuthConfig &&
        super == other &&
        other.serverTokenEndpoint == serverTokenEndpoint &&
        other.customScheme == customScheme;
  }

  @override
  int get hashCode {
    return super.hashCode ^ serverTokenEndpoint.hashCode ^ customScheme.hashCode;
  }
}

/// GitHub OAuth authentication service implementation
class GitHubAuthService implements OAuthService {
  late final GitHubOAuthClient _client;
  late final GitHubOAuthConfig _config;

  GitHubAuthService({required GitHubOAuthConfig config}) {
    _config = config;

    // Validate configuration
    if (!config.isValid()) {
      throw ArgumentError('Invalid GitHub OAuth configuration');
    }

    _client = GitHubOAuthClient(
      clientId: config.clientId,
      redirectUri: config.redirectUri,
      customScheme: config.customScheme,
      serverTokenEndpoint: config.serverTokenEndpoint,
      scopes: config.scopes,
    );
  }

  // Cache keys
  static const String _cacheKeyPrefix = 'github_auth_';
  static const String _accessTokenKey = '${_cacheKeyPrefix}access_token';
  static const String _refreshTokenKey = '${_cacheKeyPrefix}refresh_token';
  static const String _expiresAtKey = '${_cacheKeyPrefix}expires_at';
  static const String _userInfoKey = '${_cacheKeyPrefix}user_info';
  static const String _scopesKey = '${_cacheKeyPrefix}scopes';

  /// Get current configuration
  GitHubOAuthConfig get config => _config;

  @override
  String get providerName => 'github';

  @override
  String get displayName => 'GitHub';

  @override
  bool get supportsSilentSignIn => true;

  @override
  bool get supportsTokenRefresh => false; // GitHub doesn't support refresh tokens
/*
  @override
  Future<AuthResult?> signIn() async {
    try {
      // Step 1: Get authorization code from GitHub
      final authCode = await _client.getAuthorizationCode();
      if (authCode == null) {
        return AuthResult.cancelled(providerName);
      }

      // Step 2: Exchange code for token via server
      final tokenData = await _client.exchangeCodeForToken(authCode);
      if (tokenData == null) {
        return AuthResult.failure(
          provider: providerName,
          error: 'Failed to exchange code for token',
        );
      }

      // Step 3: Get user info
      final userInfo = await _client.getUserInfo();
      if (userInfo == null) {
        return AuthResult.failure(
          provider: providerName,
          error: 'Failed to get user info',
        );
      }

      // Cache authentication information
     await _cacheAuthResult(tokenData, userInfo);

      return AuthResult.success(
        provider: providerName,
        userId: userInfo['id']?.toString(),
        displayName: userInfo['name'] ?? userInfo['login'],
        email: userInfo['email'],
        photoUrl: userInfo['avatar_url'],
        // accessToken: tokenData['access_token'],
        // refreshToken: tokenData['refresh_token'],
        // expiresAt: _parseExpiresAt(tokenData),
        additionalData: {
          'github_username': userInfo['login'],
          'github_id': userInfo['id'],
          'public_repos': userInfo['public_repos'],
          'followers': userInfo['followers'],
          'following': userInfo['following'],
        },
      );
    } catch (e) {
      debugPrint('GitHub sign in error: $e');
      if (e.toString().contains('User cancelled') || e.toString().contains('cancelled')) {
        return AuthResult.cancelled(providerName);
      }
      return AuthResult.failure(
        provider: providerName,
        error: e.toString(),
      );
    }
  }
  */
  @override
  Future<AuthResult?> signIn() async {
    try {
      // Step 1: Get state code from Server
      final result = await _client.getState();

      if (result == null) {
        return AuthResult.cancelled(providerName);
      }

      return AuthResult.success(
        provider: providerName,
        idToken: result.state,
        additionalData: {
          'state': result.state,
          'isRegister': result.isRegister,
        },
      );
    } catch (e) {
      debugPrint('GitHub sign in error: $e');
      if (e.toString().contains('User cancelled') || e.toString().contains('cancelled')) {
        return AuthResult.cancelled(providerName);
      }
      return AuthResult.failure(
        provider: providerName,
        error: e.toString(),
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

      // Validate token with GitHub API
      return await _client.isTokenValid();
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    await _client.logout();
    await clearCache();
  }

  @override
  Future<AuthResult?> silentSignIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString(_accessTokenKey);
      final refreshToken = prefs.getString(_refreshTokenKey);
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
        return null; // GitHub doesn't support refresh tokens
      }

      // Validate token
      if (!await _client.isTokenValid()) {
        return null;
      }

      // Get fresh user info if needed
      if (userInfo == null) {
        userInfo = await _client.getUserInfo();
        if (userInfo != null) {
          await prefs.setString(_userInfoKey, json.encode(userInfo));
        }
      }

      return AuthResult.success(
        provider: providerName,
        userId: userInfo?['id']?.toString(),
        displayName: userInfo?['name'] ?? userInfo?['login'],
        email: userInfo?['email'],
        photoUrl: userInfo?['avatar_url'],
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        additionalData: {
          'github_username': userInfo?['login'],
          'github_id': userInfo?['id'],
          'public_repos': userInfo?['public_repos'],
          'followers': userInfo?['followers'],
          'following': userInfo?['following'],
        },
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<AuthResult?> refreshToken() async {
    // GitHub doesn't support refresh tokens
    return null;
  }

  @override
  Future<AuthResult?> getCurrentUser() async {
    return await silentSignIn();
  }

  @override
  Future<bool> revokeToken() async {
    // GitHub doesn't provide a standard token revocation endpoint
    // We just clear local cache
    await clearCache();
    return true;
  }

  @override
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_userInfoKey);
    await prefs.remove(_scopesKey);
  }

  @override
  Future<bool> validateToken() async {
    return await _client.isTokenValid();
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
    // For GitHub, we need to re-authenticate with new scopes
    // Create a new client with additional scopes
    final newScopes = {..._config.scopes, ...scopes}.toList();
    final newClient = GitHubOAuthClient(
      clientId: _config.clientId,
      redirectUri: _config.redirectUri,
      customScheme: _config.customScheme,
      serverTokenEndpoint: _config.serverTokenEndpoint,
      scopes: newScopes,
    );

    try {
      // Step 1: Get authorization code with new scopes
      final authCode = await newClient.getAuthorizationCode();
      if (authCode == null) {
        return AuthResult.cancelled(providerName);
      }

      // Step 2: Exchange code for token via server
      final tokenData = await newClient.exchangeCodeForToken(authCode);
      if (tokenData == null) {
        return AuthResult.failure(
          provider: providerName,
          error: 'Failed to exchange code for token',
        );
      }

      // Step 3: Get user info
      final userInfo = await newClient.getUserInfo();
      if (userInfo == null) {
        return AuthResult.failure(
          provider: providerName,
          error: 'Failed to get user info',
        );
      }

      // Update cache with new scopes
      await _cacheAuthResult(tokenData, userInfo, newScopes);

      return AuthResult.success(
        provider: providerName,
        userId: userInfo['id']?.toString(),
        displayName: userInfo['name'] ?? userInfo['login'],
        email: userInfo['email'],
        photoUrl: userInfo['avatar_url'],
        accessToken: tokenData['access_token'],
        refreshToken: tokenData['refresh_token'],
        expiresAt: _parseExpiresAt(tokenData),
        additionalData: {
          'github_username': userInfo['login'],
          'github_id': userInfo['id'],
          'public_repos': userInfo['public_repos'],
          'followers': userInfo['followers'],
          'following': userInfo['following'],
        },
      );
    } catch (e) {
      return AuthResult.failure(
        provider: providerName,
        error: e.toString(),
      );
    }
  }

  /// Get access token directly
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Get user info directly
  Future<Map<String, dynamic>?> getUserInfo() async {
    return await _client.getUserInfo();
  }

  /// Parse expires_at from token data
  DateTime? _parseExpiresAt(Map<String, dynamic> tokenData) {
    final expiresIn = tokenData['expires_in'];
    if (expiresIn != null) {
      final expiresInSeconds = expiresIn is int ? expiresIn : int.tryParse(expiresIn.toString());
      if (expiresInSeconds != null) {
        return DateTime.now().add(Duration(seconds: expiresInSeconds));
      }
    }
    return null;
  }

  /// Cache authentication result
  Future<void> _cacheAuthResult(
    Map<String, dynamic> tokenData,
    Map<String, dynamic> userInfo, [
    List<String>? scopes,
  ]) async {
    final prefs = await SharedPreferences.getInstance();

    if (tokenData['access_token'] != null) {
      await prefs.setString(_accessTokenKey, tokenData['access_token']);
    }

    if (tokenData['refresh_token'] != null) {
      await prefs.setString(_refreshTokenKey, tokenData['refresh_token']);
    }

    final expiresAt = _parseExpiresAt(tokenData);
    if (expiresAt != null) {
      await prefs.setString(_expiresAtKey, expiresAt.toIso8601String());
    }

    await prefs.setString(_userInfoKey, json.encode(userInfo));

    // Cache authorized permission scopes
    final scopesToCache = scopes ?? _config.scopes;
    await prefs.setString(_scopesKey, json.encode(scopesToCache));
  }
}
