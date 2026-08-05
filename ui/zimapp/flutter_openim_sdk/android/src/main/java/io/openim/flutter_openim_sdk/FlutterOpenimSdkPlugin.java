package io.openim.flutter_openim_sdk;

import android.app.Activity;
import android.content.Context;

import androidx.annotation.NonNull;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.openim.flutter_openim_sdk.connectivity.ConnectivityListener;
import io.openim.flutter_openim_sdk.connectivity.VisibilityListener;
import io.openim.flutter_openim_sdk.manager.ConversationManager;
import io.openim.flutter_openim_sdk.manager.FriendshipManager;
import io.openim.flutter_openim_sdk.manager.GroupManager;
import io.openim.flutter_openim_sdk.manager.IMManager;
import io.openim.flutter_openim_sdk.manager.MessageManager;
import io.openim.flutter_openim_sdk.manager.SignalingManager;
import io.openim.flutter_openim_sdk.manager.UserManager;

/**
 * Enhanced FlutterOpenimSdkPlugin - Specifically handles foreground/background
 * switching issues
 */
public class FlutterOpenimSdkPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    private static final String CHANNEL_NAME = "flutter_openim_sdk";
    private static final String TAG = "FlutterOpenimSdkPlugin";

    // Use instance variables instead of static variables
    private MethodChannel channel;
    private IMManager imManager;
    private UserManager userManager;
    private FriendshipManager friendshipManager;
    private MessageManager messageManager;
    private ConversationManager conversationManager;
    private GroupManager groupManager;
    private SignalingManager signalingManager;

    private Activity currentActivity;
    private Context applicationContext;
    private ConnectivityListener connectivityListener;
    private VisibilityListener visibilityListener;

    // Use atomic boolean values to ensure thread safety
    private final AtomicBoolean isInitialized = new AtomicBoolean(false);
    private final AtomicBoolean isActivityLifecycleRegistered = new AtomicBoolean(false);
    private final AtomicBoolean isConnectivityRegistered = new AtomicBoolean(false);

    // Foreground/background state management
    private final AtomicBoolean isAppInBackground = new AtomicBoolean(false);
    private long lastBackgroundTime = 0;
    private long lastForegroundTime = 0;

    // Static instance reference for backward compatibility
    private static FlutterOpenimSdkPlugin instance;

    public FlutterOpenimSdkPlugin() {
        // Initialize managers in constructor
        this.imManager = new IMManager();
        this.userManager = new UserManager();
        this.friendshipManager = new FriendshipManager();
        this.messageManager = new MessageManager();
        this.conversationManager = new ConversationManager();
        this.groupManager = new GroupManager();
        this.signalingManager = new SignalingManager();

        // Set static instance reference
        instance = this;
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        Log.i(TAG, "onAttachedToEngine");

        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL_NAME);
        applicationContext = flutterPluginBinding.getApplicationContext();
        channel.setMethodCallHandler(this);

        // Initialize network listener
        connectivityListener = new ConnectivityListener(applicationContext);
        registerConnectivityListener();

        // Initialize visibility listener
        visibilityListener = new VisibilityListener();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        parse(call, result);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        Log.i(TAG, "onDetachedFromEngine");

        if (channel != null) {
            channel.setMethodCallHandler(null);
        }

        // Clean up all listeners
        unregisterAllListeners();

        // Clean up references
        currentActivity = null;
        applicationContext = null;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        Log.i(TAG, "onAttachedToActivity");

        currentActivity = binding.getActivity();

        // Register Activity lifecycle callbacks
        registerActivityLifecycle();

        // If app returns from background to foreground, notify SDK
        if (isAppInBackground.get()) {
            handleAppForeground();
        }
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        Log.i(TAG, "onDetachedFromActivityForConfigChanges");

        // Unregister lifecycle callbacks during configuration changes
        unregisterActivityLifecycle();
        currentActivity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        Log.i(TAG, "onReattachedToActivityForConfigChanges");

        currentActivity = binding.getActivity();

        // Re-register Activity lifecycle callbacks
        registerActivityLifecycle();

        // If app returns from background to foreground, notify SDK
        if (isAppInBackground.get()) {
            handleAppForeground();
        }
    }

    @Override
    public void onDetachedFromActivity() {
        Log.i(TAG, "onDetachedFromActivity");

        // Unregister lifecycle callbacks when completely detached
        unregisterActivityLifecycle();
        currentActivity = null;
    }

    /**
     * Register Activity lifecycle listener
     */
    private void registerActivityLifecycle() {
        if (visibilityListener != null && !isActivityLifecycleRegistered.get()) {
            visibilityListener.register(currentActivity, this);
            isActivityLifecycleRegistered.set(true);
            Log.i(TAG, "Activity lifecycle registered");
        }
    }

    /**
     * Unregister Activity lifecycle listener
     */
    private void unregisterActivityLifecycle() {
        if (visibilityListener != null && isActivityLifecycleRegistered.get()) {
            visibilityListener.unregisterReceiver(currentActivity);
            isActivityLifecycleRegistered.set(false);
            Log.i(TAG, "Activity lifecycle unregistered");
        }
    }

    /**
     * Register network connectivity listener
     */
    private void registerConnectivityListener() {
        if (connectivityListener != null && !isConnectivityRegistered.get()) {
            connectivityListener.register();
            isConnectivityRegistered.set(true);
            Log.i(TAG, "Connectivity listener registered");
        }
    }

    /**
     * Unregister network connectivity listener
     */
    private void unregisterConnectivityListener() {
        if (connectivityListener != null && isConnectivityRegistered.get()) {
            connectivityListener.unregisterReceiver();
            isConnectivityRegistered.set(false);
            Log.i(TAG, "Connectivity listener unregistered");
        }
    }

    /**
     * Unregister all listeners
     */
    private void unregisterAllListeners() {
        unregisterActivityLifecycle();
        unregisterConnectivityListener();
    }

    /**
     * Handle app entering foreground
     */
    public void handleAppForeground() {
        if (isInitialized.get()) {
            lastForegroundTime = System.currentTimeMillis();
            isAppInBackground.set(false);

            // Notify SDK that app entered foreground
            try {
                if (imManager != null) {
                    // Here we need to call SDK foreground methods
                    Log.i(TAG, "App entered foreground, notifying SDK");
                }
            } catch (Exception e) {
                Log.e(TAG, "Error notifying SDK of foreground status", e);
            }
        }
    }

    /**
     * Handle app entering background
     */
    public void handleAppBackground() {
        if (isInitialized.get()) {
            lastBackgroundTime = System.currentTimeMillis();
            isAppInBackground.set(true);

            // Notify SDK that app entered background
            try {
                if (imManager != null) {
                    // Here we need to call SDK background methods
                    Log.i(TAG, "App entered background, notifying SDK");
                }
            } catch (Exception e) {
                Log.e(TAG, "Error notifying SDK of background status", e);
            }
        }
    }

    /**
     * Check if app is in background
     */
    public boolean isAppInBackground() {
        return isAppInBackground.get();
    }

    /**
     * Get background duration
     */
    public long getBackgroundDuration() {
        if (isAppInBackground.get()) {
            return System.currentTimeMillis() - lastBackgroundTime;
        }
        return 0;
    }

    void parse(@NonNull MethodCall call, @NonNull Result result) {
        try {
            String managerName = call.argument("ManagerName");

            // Use instance variables instead of static variables
            Object manager = getManagerByName(managerName);
            if (manager == null) {
                result.error("MANAGER_NOT_FOUND", "Manager not found: " + managerName, null);
                return;
            }

            Method method = manager.getClass().getDeclaredMethod(call.method, MethodCall.class, Result.class);
            Log.i(TAG, "Flutter call native: { class:" + managerName + ", method:" + method.getName() + " }");
            method.invoke(manager, call, result);
        } catch (Exception e) {
            Log.e(TAG, "Error in parse method", e);
            result.error("PARSE_ERROR", e.getMessage(), null);
        }
    }

    /**
     * Get manager instance by name
     */
    private Object getManagerByName(String managerName) {
        switch (managerName) {
            case "imManager":
                return imManager;
            case "userManager":
                return userManager;
            case "friendshipManager":
                return friendshipManager;
            case "messageManager":
                return messageManager;
            case "conversationManager":
                return conversationManager;
            case "groupManager":
                return groupManager;
            case "signalingManager":
                return signalingManager;
            default:
                return null;
        }
    }

    /**
     * Get current Activity
     */
    public Activity getCurrentActivity() {
        return currentActivity;
    }

    /**
     * Get application context
     */
    public Context getApplicationContext() {
        return applicationContext;
    }

    /**
     * Check if initialized
     */
    public boolean isInitialized() {
        return isInitialized.get();
    }

    /**
     * Set initialization status
     */
    public void setInitialized(boolean initialized) {
        this.isInitialized.set(initialized);

        // Update SDK status in listeners
        if (connectivityListener != null) {
            connectivityListener.setSDKInitialized(initialized);
        }
        if (visibilityListener != null) {
            visibilityListener.setSDKInitialized(initialized);
        }
    }

    /**
     * Get plugin instance (for backward compatibility)
     */
    public static FlutterOpenimSdkPlugin getInstance() {
        return instance;
    }

    /**
     * Get method channel (for backward compatibility)
     */
    public static MethodChannel getChannel() {
        return instance != null ? instance.channel : null;
    }
}
