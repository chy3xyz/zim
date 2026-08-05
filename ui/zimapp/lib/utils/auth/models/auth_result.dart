/// Authentication result model
///
/// Contains authentication result information, including success status, user information, tokens, etc.
class AuthResult {
  /// Whether authentication was successful
  final bool isSuccess;

  /// Whether authentication was cancelled
  final bool isCancelled;

  /// Authentication provider name
  final String provider;

  /// User ID
  final String? userId;

  /// User display name
  final String? displayName;

  /// User email
  final String? email;

  /// User avatar URL
  final String? photoUrl;

  /// Access token
  final String? accessToken;

  /// Refresh token
  final String? refreshToken;

  /// ID token
  final String? idToken;

  /// Token expiration time
  final DateTime? expiresAt;

  /// Error message
  final String? error;

  /// Error details
  final String? errorDetails;

  /// Additional data
  final Map<String, dynamic>? additionalData;

  const AuthResult._({
    required this.isSuccess,
    required this.isCancelled,
    required this.provider,
    this.userId,
    this.displayName,
    this.email,
    this.photoUrl,
    this.accessToken,
    this.refreshToken,
    this.idToken,
    this.expiresAt,
    this.error,
    this.errorDetails,
    this.additionalData,
  });

  /// Create successful authentication result
  factory AuthResult.success({
    required String provider,
    String? userId,
    String? displayName,
    String? email,
    String? photoUrl,
    String? accessToken,
    String? refreshToken,
    String? idToken,
    DateTime? expiresAt,
    Map<String, dynamic>? additionalData,
  }) {
    return AuthResult._(
      isSuccess: true,
      isCancelled: false,
      provider: provider,
      userId: userId,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: expiresAt,
      additionalData: additionalData,
    );
  }

  /// Create failed authentication result
  factory AuthResult.failure({
    required String provider,
    String? error,
    String? errorDetails,
    Map<String, dynamic>? additionalData,
  }) {
    return AuthResult._(
      isSuccess: false,
      isCancelled: false,
      provider: provider,
      error: error,
      errorDetails: errorDetails,
      additionalData: additionalData,
    );
  }

  /// Create cancelled authentication result
  factory AuthResult.cancelled(String provider) {
    return AuthResult._(
      isSuccess: false,
      isCancelled: true,
      provider: provider,
      error: 'Authentication cancelled by user',
    );
  }

  /// Whether authentication failed
  bool get isFailure => !isSuccess && !isCancelled;

  /// Whether token has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Whether token is valid (not expired and access token exists)
  bool get isValid => isSuccess && accessToken != null && !isExpired;

  /// Get user information map
  Map<String, dynamic> get userInfo => {
        'userId': userId,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
      };

  /// Get token information map
  Map<String, dynamic> get tokenInfo => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'isSuccess': isSuccess,
      'isCancelled': isCancelled,
      'provider': provider,
      'userId': userId,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'idToken': idToken,
      'expiresAt': expiresAt?.toIso8601String(),
      'error': error,
      'errorDetails': errorDetails,
      'additionalData': additionalData,
    };
  }

  /// Create from JSON
  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult._(
      isSuccess: json['isSuccess'] ?? false,
      isCancelled: json['isCancelled'] ?? false,
      provider: json['provider'] ?? '',
      userId: json['userId'],
      displayName: json['displayName'],
      email: json['email'],
      photoUrl: json['photoUrl'],
      accessToken: json['accessToken'],
      refreshToken: json['refreshToken'],
      idToken: json['idToken'],
      expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      error: json['error'],
      errorDetails: json['errorDetails'],
      additionalData: json['additionalData'],
    );
  }

  /// Copy with new values
  AuthResult copyWith({
    bool? isSuccess,
    bool? isCancelled,
    String? provider,
    String? userId,
    String? displayName,
    String? email,
    String? photoUrl,
    String? accessToken,
    String? refreshToken,
    String? idToken,
    DateTime? expiresAt,
    String? error,
    String? errorDetails,
    Map<String, dynamic>? additionalData,
  }) {
    return AuthResult._(
      isSuccess: isSuccess ?? this.isSuccess,
      isCancelled: isCancelled ?? this.isCancelled,
      provider: provider ?? this.provider,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      idToken: idToken ?? this.idToken,
      expiresAt: expiresAt ?? this.expiresAt,
      error: error ?? this.error,
      errorDetails: errorDetails ?? this.errorDetails,
      additionalData: additionalData ?? this.additionalData,
    );
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'AuthResult.success(provider: $provider, userId: $userId, displayName: $displayName, email: $email)';
    } else if (isCancelled) {
      return 'AuthResult.cancelled(provider: $provider)';
    } else {
      return 'AuthResult.failure(provider: $provider, error: $error)';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthResult &&
        other.isSuccess == isSuccess &&
        other.isCancelled == isCancelled &&
        other.provider == provider &&
        other.userId == userId &&
        other.displayName == displayName &&
        other.email == email &&
        other.photoUrl == photoUrl &&
        other.accessToken == accessToken &&
        other.refreshToken == refreshToken &&
        other.idToken == idToken &&
        other.expiresAt == expiresAt &&
        other.error == error &&
        other.errorDetails == errorDetails;
  }

  @override
  int get hashCode {
    return Object.hash(
      isSuccess,
      isCancelled,
      provider,
      userId,
      displayName,
      email,
      photoUrl,
      accessToken,
      refreshToken,
      idToken,
      expiresAt,
      error,
      errorDetails,
    );
  }
}
