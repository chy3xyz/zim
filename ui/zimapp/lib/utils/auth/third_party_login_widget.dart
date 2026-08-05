import 'package:openim_common/openim_common.dart';

// Third-party login widget with OAuth configuration support
//
// This widget provides third-party login functionality with support for Google and GitHub.
// You can customize OAuth configurations through the ThirdPartyLoginConfig class.
//
// ## Usage Examples:
//
// ### 1. Basic usage with default configurations:
// ```dart
// ThirdPartyLoginWidget(
//   onLoginSuccess: (result) {
//     print('Login successful: ${result.userInfo}');
//   },
//   onLoginFailure: (error) {
//     print('Login failed: $error');
//   },
// )
// ```
//
// ### 2. Custom Google configuration:
// ```dart
// ThirdPartyLoginWidget(
//   config: ThirdPartyLoginConfig.google(
//     clientId: 'your-google-client-id',
//     redirectUri: 'your-redirect-uri',
//     scopes: ['openid', 'profile', 'email'],
//   ),
//   onLoginSuccess: (result) {
//     // Handle success
//   },
// )
// ```
//
// ### 3. Custom GitHub configuration:
// ```dart
// ThirdPartyLoginWidget(
//   config: ThirdPartyLoginConfig.github(
//     clientId: 'your-github-client-id',
//     clientSecret: 'your-github-client-secret',
//     redirectUri: 'your-redirect-uri',
//     scopes: ['user:email', 'read:user'],
//   ),
//   onLoginSuccess: (result) {
//     // Handle success
//   },
// )
// ```
//
// ### 4. Both Google and GitHub configurations:
// ```dart
// ThirdPartyLoginWidget(
//   config: ThirdPartyLoginConfig.both(
//     googleClientId: 'your-google-client-id',
//     googleRedirectUri: 'your-google-redirect-uri',
//     githubClientId: 'your-github-client-id',
//     githubClientSecret: 'your-github-client-secret',
//     githubRedirectUri: 'your-github-redirect-uri',
//     githubCustomScheme: 'your-github-custom-scheme',
//   ),
//   onLoginSuccess: (result) {
//     // Handle success
//   },
// )
// ```
//
// ### 5. Global configuration setup (recommended for app initialization):
// ```dart
// In your main.dart or app initialization
// ThirdPartyLoginConfig.setupDevelopment(
//   googleClientId: 'your-dev-google-client-id',
//   googleRedirectUri: 'your-dev-google-redirect-uri',
//   githubClientId: 'your-dev-github-client-id',
//   githubClientSecret: 'your-dev-github-client-secret',
//   githubRedirectUri: 'your-dev-github-redirect-uri',
//   githubCustomScheme: 'your-github-custom-scheme',
// );
//
// Then use the widget without config parameter
// ThirdPartyLoginWidget(
//   onLoginSuccess: (result) {
//     // Handle success
//   },
// )
// ```

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'services/oauth_service_factory.dart';
import 'services/oauth_service.dart';
import 'services/google_auth_service.dart';
import 'services/github_oauth2_client_service.dart';
import 'services/github_auth_service.dart' as secure_github;
import 'models/auth_result.dart';

/// Third-party login widget configuration
class ThirdPartyLoginConfig {
  /// Google OAuth configuration
  final GoogleOAuthConfig? googleConfig;

  /// GitHub OAuth configuration (oauth2_client)
  final GitHubOAuthConfig? githubConfig;

  /// GitHub OAuth configuration (secure with server-side token exchange)
  final secure_github.GitHubOAuthConfig? githubSecureConfig;

  /// Custom OAuth service configurations
  final Map<OAuthProvider, OAuthServiceConfig>? customConfigs;

  const ThirdPartyLoginConfig({
    this.googleConfig,
    this.githubConfig,
    this.githubSecureConfig,
    this.customConfigs,
  });

  /// Setup OAuth configurations globally
  static void setupGlobalConfigurations(ThirdPartyLoginConfig config) {
    final factory = OAuthServiceFactory();

    // Register Google service with custom config
    if (config.googleConfig != null) {
      final googleService = GoogleAuthService(config: config.googleConfig!);
      factory.registerCustomService(OAuthProvider.google, googleService);
    }

    // Register GitHub service with custom config
    if (config.githubConfig != null) {
      final githubService = GitHubOAuth2ClientService(config: config.githubConfig!);
      factory.registerCustomService(OAuthProvider.github, githubService);
    }

    // Register GitHub Secure service with custom config
    if (config.githubSecureConfig != null) {
      final githubSecureService = secure_github.GitHubAuthService(config: config.githubSecureConfig!);
      factory.registerCustomService(OAuthProvider.githubSecure, githubSecureService);
    }

    // Register other custom services
    if (config.customConfigs != null) {
      for (final entry in config.customConfigs!.entries) {
        final provider = entry.key;
        final serviceConfig = entry.value;

        // Create service with custom config using factory method
        final service = factory.createServiceWithConfig(provider, serviceConfig);
        factory.registerCustomService(provider, service);
      }
    }
  }

  /// Quick setup for development environment
  static void setupDevelopment({
    required String googleClientId,
    required String googleRedirectUri,
    required String githubClientId,
    String? githubClientSecret,
    required String githubRedirectUri,
    required String githubCustomScheme,
  }) {
    final config = ThirdPartyLoginConfig.both(
      googleClientId: googleClientId,
      googleRedirectUri: googleRedirectUri,
      githubClientId: githubClientId,
      githubClientSecret: githubClientSecret,
      githubRedirectUri: githubRedirectUri,
      githubCustomScheme: githubCustomScheme,
    );
    setupGlobalConfigurations(config);
  }

  /// Quick setup for production environment
  static void setupProduction({
    required String googleClientId,
    required String googleRedirectUri,
    required String githubClientId,
    String? githubClientSecret,
    required String githubRedirectUri,
    required String githubCustomScheme,
  }) {
    final config = ThirdPartyLoginConfig.both(
      googleClientId: googleClientId,
      googleRedirectUri: googleRedirectUri,
      githubClientId: githubClientId,
      githubClientSecret: githubClientSecret,
      githubRedirectUri: githubRedirectUri,
      githubCustomScheme: githubCustomScheme,
    );
    setupGlobalConfigurations(config);
  }

  /// Create configuration with Google settings
  factory ThirdPartyLoginConfig.google({
    required String clientId,
    required String redirectUri,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? tokenEndpoint,
    String? userInfoEndpoint,
    String? revocationEndpoint,
    bool? usePkce,
    Map<String, String>? additionalParameters,
  }) {
    return ThirdPartyLoginConfig(
      googleConfig: GoogleOAuthConfig(
        clientId: clientId,
        redirectUri: redirectUri,
        scopes: scopes,
        authorizationEndpoint: authorizationEndpoint,
        tokenEndpoint: tokenEndpoint,
        userInfoEndpoint: userInfoEndpoint,
        revocationEndpoint: revocationEndpoint,
        usePkce: usePkce,
        additionalParameters: additionalParameters,
      ),
    );
  }

  /// Create configuration with GitHub settings
  factory ThirdPartyLoginConfig.github({
    required String clientId,
    required String redirectUri,
    required String customScheme,
    String? clientSecret,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? tokenEndpoint,
    String? userInfoEndpoint,
    String? revocationEndpoint,
    bool? usePkce,
    Map<String, String>? additionalParameters,
  }) {
    return ThirdPartyLoginConfig(
      githubConfig: GitHubOAuthConfig(
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        customScheme: customScheme,
        scopes: scopes,
        authorizationEndpoint: authorizationEndpoint,
        tokenEndpoint: tokenEndpoint,
        userInfoEndpoint: userInfoEndpoint,
        revocationEndpoint: revocationEndpoint,
        usePkce: usePkce,
        additionalParameters: additionalParameters,
      ),
    );
  }

  /// Create configuration with GitHub Secure settings
  factory ThirdPartyLoginConfig.githubSecure({
    required String clientId,
    required String redirectUri,
    required String serverTokenEndpoint,
    required String customScheme,
    List<String>? scopes,
    String? authorizationEndpoint,
    String? userInfoEndpoint,
    String? revocationEndpoint,
    bool? usePkce,
  }) {
    return ThirdPartyLoginConfig(
      githubSecureConfig: secure_github.GitHubOAuthConfig(
        clientId: clientId,
        redirectUri: redirectUri,
        serverTokenEndpoint: serverTokenEndpoint,
        customScheme: customScheme,
        scopes: scopes ?? const ['user:email', 'read:user'],
        authorizationEndpoint: authorizationEndpoint ?? 'https://github.com/login/oauth/authorize',
        userInfoEndpoint: userInfoEndpoint ?? 'https://api.github.com/user',
        usePkce: usePkce,
      ),
    );
  }

  /// Create configuration with both Google and GitHub settings
  factory ThirdPartyLoginConfig.both({
    // Google settings
    required String googleClientId,
    required String googleRedirectUri,
    String? googleClientSecret,
    List<String>? googleScopes,
    String? googleAuthorizationEndpoint,
    String? googleTokenEndpoint,
    String? googleUserInfoEndpoint,
    String? googleRevocationEndpoint,
    bool? googleUsePkce,
    Map<String, String>? googleAdditionalParameters,
    // GitHub settings
    required String githubClientId,
    required String githubRedirectUri,
    required String githubCustomScheme,
    String? githubClientSecret,
    List<String>? githubScopes,
    String? githubAuthorizationEndpoint,
    String? githubTokenEndpoint,
    String? githubUserInfoEndpoint,
    String? githubRevocationEndpoint,
    bool? githubUsePkce,
    String? githubServerTokenEndpoint,
    Map<String, String>? githubAdditionalParameters,
  }) {
    return ThirdPartyLoginConfig(
      googleConfig: GoogleOAuthConfig(
        clientId: googleClientId,
        redirectUri: googleRedirectUri,
        scopes: googleScopes,
        authorizationEndpoint: googleAuthorizationEndpoint,
        tokenEndpoint: googleTokenEndpoint,
        userInfoEndpoint: googleUserInfoEndpoint,
        revocationEndpoint: googleRevocationEndpoint,
        usePkce: googleUsePkce,
        additionalParameters: googleAdditionalParameters,
      ),
      githubConfig: githubClientSecret != null
          ? GitHubOAuthConfig(
              clientId: githubClientId,
              clientSecret: githubClientSecret,
              redirectUri: githubRedirectUri,
              customScheme: githubCustomScheme,
              scopes: githubScopes,
              authorizationEndpoint: githubAuthorizationEndpoint,
              tokenEndpoint: githubTokenEndpoint,
              userInfoEndpoint: githubUserInfoEndpoint,
              revocationEndpoint: githubRevocationEndpoint,
              usePkce: githubUsePkce,
              additionalParameters: githubAdditionalParameters,
            )
          : null,
      githubSecureConfig: githubServerTokenEndpoint != null
          ? secure_github.GitHubOAuthConfig(
              clientId: githubClientId,
              redirectUri: githubRedirectUri,
              serverTokenEndpoint: githubServerTokenEndpoint,
              customScheme: githubCustomScheme,
              scopes: githubScopes,
              authorizationEndpoint: githubAuthorizationEndpoint,
              userInfoEndpoint: githubUserInfoEndpoint,
              usePkce: githubUsePkce,
            )
          : null,
    );
  }
}

/// Third-party login widget
///
/// Provides third-party login functionality, supports Google and GitHub login
class ThirdPartyLoginWidget extends StatefulWidget {
  /// Callback when login is successful
  final Function(AuthResult result)? onLoginSuccess;

  /// Callback when login fails
  final Function(String error)? onLoginFailure;

  /// Callback when login is cancelled
  final VoidCallback? onLoginCancelled;

  /// Whether to show loading state
  final bool showLoading;

  /// Custom button style
  final ButtonStyle? buttonStyle;

  /// Custom button text style
  final TextStyle? buttonTextStyle;

  /// Button spacing
  final double buttonSpacing;

  /// Whether to show button text
  final bool showButtonText;

  /// Custom button height
  final double? buttonHeight;

  /// Custom button width
  final double? buttonWidth;

  /// Enabled providers
  final List<OAuthProvider> enabledProviders;

  /// OAuth configuration
  final ThirdPartyLoginConfig? config;

  const ThirdPartyLoginWidget({
    super.key,
    this.onLoginSuccess,
    this.onLoginFailure,
    this.onLoginCancelled,
    this.showLoading = true,
    this.buttonStyle,
    this.buttonTextStyle,
    this.buttonSpacing = 16.0,
    this.showButtonText = false,
    this.buttonHeight,
    this.buttonWidth,
    this.enabledProviders = const [OAuthProvider.google, OAuthProvider.githubSecure],
    this.config,
  });

  @override
  State<ThirdPartyLoginWidget> createState() => _ThirdPartyLoginWidgetState();
}

class _ThirdPartyLoginWidgetState extends State<ThirdPartyLoginWidget> {
  final OAuthServiceManager _authManager = OAuthServiceManager();
  final Map<OAuthProvider, bool> _loadingStates = {};

  @override
  void initState() {
    super.initState();
    // Initialize loading states
    for (final provider in widget.enabledProviders) {
      _loadingStates[provider] = false;
    }
    // Setup custom configurations
    _setupCustomConfigurations();
  }

  /// Setup custom OAuth configurations
  void _setupCustomConfigurations() {
    if (widget.config == null) return;

    final factory = OAuthServiceFactory();

    // Register Google service with custom config
    if (widget.config!.googleConfig != null) {
      final googleService = GoogleAuthService(config: widget.config!.googleConfig!);
      factory.registerCustomService(OAuthProvider.google, googleService);
    }

    // Register GitHub service with custom config
    if (widget.config!.githubConfig != null) {
      final githubService = GitHubOAuth2ClientService(config: widget.config!.githubConfig!);
      factory.registerCustomService(OAuthProvider.github, githubService);
    }

    // Register GitHub Secure service with custom config
    if (widget.config!.githubSecureConfig != null) {
      final githubSecureService = secure_github.GitHubAuthService(config: widget.config!.githubSecureConfig!);
      factory.registerCustomService(OAuthProvider.githubSecure, githubSecureService);
    }

    // Register other custom services
    if (widget.config!.customConfigs != null) {
      for (final entry in widget.config!.customConfigs!.entries) {
        final provider = entry.key;
        final config = entry.value;

        // Create service with custom config using factory method
        final service = factory.createServiceWithConfig(provider, config);
        factory.registerCustomService(provider, service);
      }
    }
  }

  /// Handle login for specified provider
  Future<void> _handleLogin(OAuthProvider provider) async {
    if (_loadingStates[provider] == true) return;

    // Special handling for email login
    if (provider == OAuthProvider.email) {
      _handleEmailLogin();
      return;
    }

    setState(() {
      _loadingStates[provider] = true;
    });

    try {
      // First check if user is already signed in
      final isAlreadySignedIn = await _authManager.isSignedIn(provider);

      AuthResult? result;
      if (isAlreadySignedIn) {
        // Try silent sign-in first to avoid showing account selection dialog
        result = await _authManager.silentSignIn(provider);

        // If silent sign-in fails, fall back to regular sign-in
        if (result == null || !result.isSuccess) {
          result = await _authManager.signIn(provider);
        }
      } else {
        // User not signed in, proceed with regular sign-in
        result = await _authManager.signIn(provider);
      }

      if (result != null) {
        if (result.isSuccess) {
          widget.onLoginSuccess?.call(result);
        } else if (result.isCancelled) {
          // User cancelled login - this is normal behavior, just call the callback
          widget.onLoginCancelled?.call();
        } else {
          widget.onLoginFailure?.call(result.error ?? 'Login failed');
        }
      } else {
        widget.onLoginFailure?.call('Login failed');
      }
    } catch (e) {
      // Check if this is a user cancellation
      if (e.toString().contains('User cancelled') ||
          e.toString().contains('FlutterAppAuthUserCancelledException') ||
          e.toString().contains('WebAuthenticationSession Code=1') ||
          e.toString().contains('cancelled') ||
          e.toString().contains('canceled')) {
        // User cancelled - this is normal behavior
        widget.onLoginCancelled?.call();
      } else {
        // Actual error occurred
        widget.onLoginFailure?.call('Login error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingStates[provider] = false;
        });
      }
    }
  }

  /// Handle email login - placeholder implementation
  void _handleEmailLogin() {
    // For now, just show a message that email login is not implemented
    // In a real implementation, this would navigate to an email login page
    widget.onLoginFailure?.call('Unimplemented email login');
  }

  /// Build login button - circular icon style
  Widget _buildLoginButton({
    required OAuthProvider provider,
    required String text,
    Color? textColor,
    Color? backgroundColor,
    String? iconPath,
    IconData? icon,
  }) {
    assert(iconPath != null || icon != null, 'Either iconPath or icon must be provided');

    final isLoading = _loadingStates[provider] ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.buttonWidth ?? 42.w,
          height: widget.buttonHeight ?? 42.h,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLoading ? null : () => _handleLogin(provider),
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: isLoading && widget.showLoading
                    ? Center(
                        child: SizedBox(
                          height: 20.h,
                          width: 20.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(textColor ?? Colors.black),
                          ),
                        ),
                      )
                    : Center(
                        child: iconPath != null
                            ? iconPath.toImage
                            : Icon(
                                icon,
                                size: 24.h,
                                color: textColor ?? Colors.black,
                              ),
                      ),
              ),
            ),
          ),
        ),
        if (widget.showButtonText) ...[
          SizedBox(height: 8.h),
          Text(
            text,
            style: widget.buttonTextStyle ??
                TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade600,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Build Email login button
  Widget _buildEmailButton() {
    return _buildLoginButton(
      provider: OAuthProvider.email,
      text: 'Email',
      iconPath: ImageRes.emailLoginIcon,
      textColor: const Color(0xFF666666),
    );
  }

  /// Build Google login button
  Widget _buildGoogleButton() {
    return _buildLoginButton(
      provider: OAuthProvider.google,
      text: 'Google',
      iconPath: ImageRes.googleLoginIcon,
      textColor: const Color(0xFF4285F4),
    );
  }

  /// Build GitHub login button
  Widget _buildGitHubButton() {
    return _buildLoginButton(
      provider: OAuthProvider.github,
      text: 'GitHub',
      iconPath: ImageRes.githubLoginIcon,
      textColor: const Color(0xFF24292E),
    );
  }

  /// Build GitHub Secure login button
  Widget _buildGitHubSecureButton() {
    return _buildLoginButton(
      provider: OAuthProvider.githubSecure,
      text: 'GitHub',
      iconPath: ImageRes.githubLoginIcon,
      backgroundColor: Colors.grey.shade100,
      textColor: const Color(0xFF24292E),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttons = [
      if (widget.enabledProviders.contains(OAuthProvider.email)) _buildEmailButton(),
      if (widget.enabledProviders.contains(OAuthProvider.google)) _buildGoogleButton(),
      if (widget.enabledProviders.contains(OAuthProvider.github)) _buildGitHubButton(),
      if (widget.enabledProviders.contains(OAuthProvider.githubSecure)) _buildGitHubSecureButton(),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.grey,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Text(
                  StrRes.otherLogin,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.grey,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: buttons,
          ),
        ],
      ),
    );
  }
}

/// Third-party login controller
///
/// Manages third-party login state and logic
class ThirdPartyLoginController extends GetxController {
  final OAuthServiceManager _authManager = OAuthServiceManager();

  /// Current login state
  final Rx<AuthResult?> currentAuthResult = Rx<AuthResult?>(null);

  /// Loading state
  final RxBool isLoading = false.obs;

  /// Error message
  final RxString errorMessage = ''.obs;

  /// Setup custom OAuth configurations
  void setupCustomConfigurations(ThirdPartyLoginConfig config) {
    final factory = OAuthServiceFactory();

    // Register Google service with custom config
    if (config.googleConfig != null) {
      final googleService = GoogleAuthService(config: config.googleConfig!);
      factory.registerCustomService(OAuthProvider.google, googleService);
    }

    // Register GitHub service with custom config
    if (config.githubConfig != null) {
      final githubService = GitHubOAuth2ClientService(config: config.githubConfig!);
      factory.registerCustomService(OAuthProvider.github, githubService);
    }

    // Register GitHub Secure service with custom config
    if (config.githubSecureConfig != null) {
      final githubSecureService = secure_github.GitHubAuthService(config: config.githubSecureConfig!);
      factory.registerCustomService(OAuthProvider.githubSecure, githubSecureService);
    }

    // Register other custom services
    if (config.customConfigs != null) {
      for (final entry in config.customConfigs!.entries) {
        final provider = entry.key;
        final config = entry.value;

        // Create service with custom config using factory method
        final service = factory.createServiceWithConfig(provider, config);
        factory.registerCustomService(provider, service);
      }
    }
  }

  /// Execute login
  Future<void> signIn(OAuthProvider provider) async {
    try {
      isLoading.value = true;
      errorMessage.value = '';

      // First check if user is already signed in
      final isAlreadySignedIn = await _authManager.isSignedIn(provider);

      AuthResult? result;
      if (isAlreadySignedIn) {
        // Try silent sign-in first to avoid showing account selection dialog
        result = await _authManager.silentSignIn(provider);

        // If silent sign-in fails, fall back to regular sign-in
        if (result == null || !result.isSuccess) {
          result = await _authManager.signIn(provider);
        }
      } else {
        // User not signed in, proceed with regular sign-in
        result = await _authManager.signIn(provider);
      }

      if (result != null) {
        currentAuthResult.value = result;
        if (!result.isSuccess) {
          errorMessage.value = result.error ?? 'Login failed';
        }
      } else {
        errorMessage.value = 'Login failed';
      }
    } catch (e) {
      errorMessage.value = 'Login error: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// Execute logout
  Future<void> signOut(OAuthProvider provider) async {
    try {
      isLoading.value = true;
      await _authManager.signOut(provider);
      currentAuthResult.value = null;
    } catch (e) {
      errorMessage.value = 'Logout error: $e';
    } finally {
      isLoading.value = false;
    }
  }

  /// Check login status
  Future<bool> isSignedIn(OAuthProvider provider) async {
    try {
      return await _authManager.isSignedIn(provider);
    } catch (e) {
      return false;
    }
  }

  /// Try silent login
  Future<void> trySilentSignIn(OAuthProvider provider) async {
    try {
      isLoading.value = true;
      final result = await _authManager.silentSignIn(provider);
      if (result != null && result.isSuccess) {
        currentAuthResult.value = result;
      }
    } catch (e) {
      // Ignore silent login errors
    } finally {
      isLoading.value = false;
    }
  }

  /// Clear error message
  void clearError() {
    errorMessage.value = '';
  }

  /// Reset state
  void reset() {
    currentAuthResult.value = null;
    isLoading.value = false;
    errorMessage.value = '';
  }
}
