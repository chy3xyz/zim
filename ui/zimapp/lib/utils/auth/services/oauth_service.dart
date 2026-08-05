import '../models/auth_result.dart';

/// OAuth authentication service abstract interface
///
/// Defines standard methods for third-party authentication services, including login, logout, silent login, and other features
abstract class OAuthService {
  /// Authentication service provider name (e.g., google, github)
  String get providerName;

  /// Authentication service display name (e.g., Google, GitHub)
  String get displayName;

  /// Whether silent sign-in is supported
  bool get supportsSilentSignIn;

  /// Whether token refresh is supported
  bool get supportsTokenRefresh;

  /// Execute sign-in operation
  ///
  /// Returns [AuthResult] containing authentication result information
  /// Returns [AuthResult.cancelled] if user cancels sign-in
  /// Returns [AuthResult.failure] if sign-in fails
  Future<AuthResult?> signIn();

  /// Check if user is signed in
  ///
  /// Returns true if user is signed in and token is valid
  /// Returns false if user is not signed in or token has expired
  Future<bool> isSignedIn();

  /// Execute sign-out operation
  ///
  /// Clears locally stored authentication information
  /// Also revokes server-side tokens if possible
  Future<void> signOut();

  /// Silent sign-in
  ///
  /// Attempts silent sign-in using stored tokens
  /// Returns [AuthResult] if token is valid
  /// Returns null if token is invalid or doesn't exist
  Future<AuthResult?> silentSignIn();

  /// Refresh access token
  ///
  /// Uses refresh token to obtain new access token
  /// Returns new [AuthResult] if refresh is successful
  /// Returns null if refresh fails
  Future<AuthResult?> refreshToken();

  /// Get current user information
  ///
  /// Returns information of currently signed-in user
  /// Returns null if user is not signed in
  Future<AuthResult?> getCurrentUser();

  /// Revoke token
  ///
  /// Revokes all tokens for current user
  /// This will invalidate tokens on all clients
  Future<bool> revokeToken();

  /// Clear local cache
  ///
  /// Clears locally stored authentication information, but doesn't revoke server-side tokens
  Future<void> clearCache();

  /// Validate token validity
  ///
  /// Validates whether current token is still valid
  /// Returns true if token is valid
  Future<bool> validateToken();

  /// Get user permission scopes
  ///
  /// Returns list of permission scopes authorized by current user
  Future<List<String>> getGrantedScopes();

  /// Check if specific permission exists
  ///
  /// Checks if current user has authorized specific permission scope
  Future<bool> hasScope(String scope);

  /// Request additional permissions
  ///
  /// Requests user to authorize additional permission scopes
  /// Returns updated [AuthResult]
  Future<AuthResult?> requestAdditionalScopes(List<String> scopes);
}

/// OAuth service exception
class OAuthException implements Exception {
  final String message;
  final String? code;
  final String? provider;
  final dynamic originalError;

  const OAuthException({
    required this.message,
    this.code,
    this.provider,
    this.originalError,
  });

  @override
  String toString() {
    return 'OAuthException: $message${code != null ? ' (code: $code)' : ''}${provider != null ? ' (provider: $provider)' : ''}';
  }
}

/// OAuth service status
enum OAuthServiceStatus {
  /// Uninitialized
  uninitialized,

  /// Initializing
  initializing,

  /// Initialized
  initialized,

  /// Initialization failed
  initializationFailed,

  /// Signing in
  signingIn,

  /// Signed in
  signedIn,

  /// Signing out
  signingOut,

  /// Signed out
  signedOut,

  /// Refreshing token
  refreshingToken,

  /// Error state
  error,
}

/// OAuth service configuration base class
///
/// Provides basic configuration for OAuth services, specific services can inherit this class and override related properties
class OAuthServiceConfig {
  /// Service provider name
  final String providerName;

  /// Client ID
  final String clientId;

  /// Client secret (optional, usually not needed for mobile apps)
  final String? clientSecret;

  /// Redirect URI
  final String redirectUri;

  /// Permission scopes
  final List<String> scopes;

  /// Authorization endpoint
  final String authorizationEndpoint;

  /// Token endpoint
  final String? tokenEndpoint;

  /// User info endpoint
  final String? userInfoEndpoint;

  /// Revocation endpoint
  final String? revocationEndpoint;

  /// Whether to use PKCE
  final bool usePkce;

  /// Additional parameters
  final Map<String, String> additionalParameters;

  /// Constructor
  const OAuthServiceConfig({
    required this.providerName,
    required this.clientId,
    required this.redirectUri,
    required this.authorizationEndpoint,
    required this.scopes,
    this.clientSecret,
    this.tokenEndpoint,
    this.userInfoEndpoint,
    this.revocationEndpoint,
    this.usePkce = true,
    this.additionalParameters = const {},
  });

  /// Validate if configuration is valid
  bool isValid() {
    return clientId.isNotEmpty && redirectUri.isNotEmpty && authorizationEndpoint.isNotEmpty;
  }

  /// Get complete authorization URL
  String getAuthorizationUrl({
    required String state,
    String? codeChallenge,
    String? codeChallengeMethod,
  }) {
    final uri = Uri.parse(authorizationEndpoint);
    final queryParams = <String, String>{
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'scope': scopes.join(' '),
      'state': state,
      ...additionalParameters,
    };

    if (usePkce && codeChallenge != null) {
      queryParams['code_challenge'] = codeChallenge;
      queryParams['code_challenge_method'] = codeChallengeMethod ?? 'S256';
    }

    return uri.replace(queryParameters: queryParams).toString();
  }

  /// Get token request parameters
  Map<String, String> getTokenRequestParams({
    required String authorizationCode,
    String? codeVerifier,
  }) {
    final params = <String, String>{
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': authorizationCode,
      'redirect_uri': redirectUri,
    };

    if (clientSecret != null) {
      params['client_secret'] = clientSecret!;
    }

    if (usePkce && codeVerifier != null) {
      params['code_verifier'] = codeVerifier;
    }

    return params;
  }

  /// Get refresh token request parameters
  Map<String, String> getRefreshTokenRequestParams({
    required String refreshToken,
  }) {
    final params = <String, String>{
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': refreshToken,
    };

    if (clientSecret != null) {
      params['client_secret'] = clientSecret!;
    }

    return params;
  }

  /// Get revoke token request parameters
  Map<String, String> getRevokeTokenRequestParams({
    required String token,
    String tokenTypeHint = 'access_token',
  }) {
    final params = <String, String>{
      'token': token,
      'token_type_hint': tokenTypeHint,
    };

    if (clientSecret != null) {
      params['client_secret'] = clientSecret!;
    }

    return params;
  }

  /// Copy configuration and modify some properties
  OAuthServiceConfig copyWith({
    String? providerName,
    String? clientId,
    String? clientSecret,
    String? redirectUri,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? tokenEndpoint,
    String? userInfoEndpoint,
    String? revocationEndpoint,
    bool? usePkce,
    Map<String, String>? additionalParameters,
  }) {
    return OAuthServiceConfig(
      providerName: providerName ?? this.providerName,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      redirectUri: redirectUri ?? this.redirectUri,
      scopes: scopes ?? this.scopes,
      authorizationEndpoint: authorizationEndpoint ?? this.authorizationEndpoint,
      tokenEndpoint: tokenEndpoint ?? this.tokenEndpoint,
      userInfoEndpoint: userInfoEndpoint ?? this.userInfoEndpoint,
      revocationEndpoint: revocationEndpoint ?? this.revocationEndpoint,
      usePkce: usePkce ?? this.usePkce,
      additionalParameters: additionalParameters ?? this.additionalParameters,
    );
  }

  @override
  String toString() {
    return 'OAuthServiceConfig(providerName: $providerName, clientId: $clientId, redirectUri: $redirectUri, scopes: $scopes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OAuthServiceConfig &&
        other.providerName == providerName &&
        other.clientId == clientId &&
        other.redirectUri == redirectUri &&
        other.scopes.toString() == scopes.toString();
  }

  @override
  int get hashCode {
    return providerName.hashCode ^ clientId.hashCode ^ redirectUri.hashCode ^ scopes.toString().hashCode;
  }
}
