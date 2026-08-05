import 'oauth_service.dart';
import 'google_auth_service.dart';
import 'github_oauth2_client_service.dart';
import 'github_auth_service.dart' as secure_github;
import '../models/auth_result.dart';

/// OAuth service provider enumeration
enum OAuthProvider {
  email, // Email login (custom implementation)
  google,
  github, // Uses oauth2_client GitHub service
  githubSecure, // Uses secure GitHub OAuth service with server-side token exchange
}

/// OAuth service factory class
///
/// Responsible for creating and managing different OAuth service instances
class OAuthServiceFactory {
  // Singleton instance
  static final OAuthServiceFactory _instance = OAuthServiceFactory._internal();
  factory OAuthServiceFactory() => _instance;
  OAuthServiceFactory._internal();

  // Service instance cache
  final Map<OAuthProvider, OAuthService> _services = {};

  /// Get OAuth service instance for specified provider
  OAuthService? getService(OAuthProvider provider) {
    return _services[provider];
  }

  /// Get all available OAuth services
  List<OAuthService> getAllServices() {
    return OAuthProvider.values.map((provider) => getService(provider)).whereType<OAuthService>().toList();
  }

  /// Clear all service caches
  void clearAllCache() {
    _services.clear();
  }

  /// Register custom OAuth service
  void registerCustomService(OAuthProvider provider, OAuthService service) {
    _services[provider] = service;
  }

  /// Create service with custom configuration
  OAuthService createServiceWithConfig(OAuthProvider provider, OAuthServiceConfig config) {
    switch (provider) {
      case OAuthProvider.email:
        // Email login implementation can be added here
        throw UnimplementedError('Email login service not implemented yet');
      case OAuthProvider.google:
        if (config is GoogleOAuthConfig) {
          return GoogleAuthService(config: config);
        }
        throw ArgumentError('Invalid config type for Google provider');
      case OAuthProvider.github:
        if (config is GitHubOAuthConfig) {
          return GitHubOAuth2ClientService(config: config);
        }
        throw ArgumentError('Invalid config type for GitHub provider');
      case OAuthProvider.githubSecure:
        if (config is secure_github.GitHubOAuthConfig) {
          return secure_github.GitHubAuthService(config: config);
        }
        throw ArgumentError('Invalid config type for GitHub Secure provider');
    }
  }
}

/// OAuth service manager
///
/// Provides convenient OAuth service management functionality
class OAuthServiceManager {
  final OAuthServiceFactory _factory = OAuthServiceFactory();

  /// Execute sign-in for specified provider
  Future<AuthResult?> signIn(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.signIn();
  }

  /// Execute sign-out for specified provider
  Future<void> signOut(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    await service?.signOut();
  }

  /// Check if specified provider is signed in
  Future<bool> isSignedIn(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.isSignedIn() ?? false;
  }

  /// Execute silent sign-in for specified provider
  Future<AuthResult?> silentSignIn(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.silentSignIn();
  }

  /// Refresh token for specified provider
  Future<AuthResult?> refreshToken(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.refreshToken();
  }

  /// Get current user information for specified provider
  Future<AuthResult?> getCurrentUser(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.getCurrentUser();
  }

  /// Revoke token for specified provider
  Future<bool> revokeToken(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.revokeToken() ?? false;
  }

  /// Clear cache for specified provider
  Future<void> clearCache(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    await service?.clearCache();
  }

  /// Validate token for specified provider
  Future<bool> validateToken(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.validateToken() ?? false;
  }

  /// Get authorization scopes for specified provider
  Future<List<String>> getGrantedScopes(OAuthProvider provider) async {
    final service = _factory.getService(provider);
    return await service?.getGrantedScopes() ?? [];
  }

  /// Check if specified provider has specific permission
  Future<bool> hasScope(OAuthProvider provider, String scope) async {
    final service = _factory.getService(provider);
    return await service?.hasScope(scope) ?? false;
  }

  /// Request additional permissions for specified provider
  Future<AuthResult?> requestAdditionalScopes(OAuthProvider provider, List<String> scopes) async {
    final service = _factory.getService(provider);
    return await service?.requestAdditionalScopes(scopes);
  }

  /// Sign out all signed-in services
  Future<void> signOutAll() async {
    final services = _factory.getAllServices();

    for (final service in services) {
      try {
        if (await service.isSignedIn()) {
          await service.signOut();
        }
      } catch (e) {
        // Ignore errors, continue signing out other services
      }
    }
  }
}
