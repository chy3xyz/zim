package io.openim.flutter_openim_sdk.connectivity;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.Log;
import io.openim.flutter_openim_sdk.FlutterOpenimSdkPlugin;
import open_im_sdk.Open_im_sdk;

/**
 * Enhanced visibility listener - Specifically handles foreground/background
 * switching issues
 */
public class VisibilityListener implements Application.ActivityLifecycleCallbacks, open_im_sdk_callback.Base {
    private static final String TAG = "VisibilityListener";

    private boolean isRegistered = false;
    private Application application;
    private boolean isSDKInitialized = false;
    private FlutterOpenimSdkPlugin plugin;

    // Foreground/background state management
    private int activityCount = 0;
    private boolean isAppInForeground = false;
    private long lastForegroundTime = 0;
    private long lastBackgroundTime = 0;

    /**
     * Register Activity lifecycle callbacks
     */
    public void register(Activity activity, FlutterOpenimSdkPlugin plugin) {
        if (activity != null && !isRegistered) {
            this.plugin = plugin;
            this.application = activity.getApplication();
            this.application.registerActivityLifecycleCallbacks(this);
            this.isRegistered = true;
            Log.i(TAG, "Activity lifecycle callbacks registered");
        }
    }

    /**
     * Unregister Activity lifecycle callbacks
     */
    public void unregisterReceiver(Activity activity) {
        if (application != null && isRegistered) {
            application.unregisterActivityLifecycleCallbacks(this);
            this.isRegistered = false;
            this.application = null;
            this.plugin = null;
            Log.i(TAG, "Activity lifecycle callbacks unregistered");
        }
    }

    /**
     * Set SDK initialization status
     */
    public void setSDKInitialized(boolean initialized) {
        this.isSDKInitialized = initialized;
    }

    @Override
    public void onActivityCreated(@NonNull Activity activity, @Nullable Bundle savedInstanceState) {
        Log.i(TAG, "onActivityCreated: " + activity.getClass().getSimpleName());
    }

    @Override
    public void onActivityStarted(@NonNull Activity activity) {
        Log.i(TAG, "onActivityStarted: " + activity.getClass().getSimpleName());

        // Increment Activity count
        activityCount++;

        // If returning from background to foreground
        if (!isAppInForeground && activityCount > 0) {
            handleAppForeground();
        }
    }

    @Override
    public void onActivityResumed(@NonNull Activity activity) {
        Log.i(TAG, "onActivityResumed: " + activity.getClass().getSimpleName());

        // Ensure app is in foreground state
        if (!isAppInForeground) {
            handleAppForeground();
        }

        // Notify SDK that app is in foreground
        if (isSDKInitialized) {
            try {
                Open_im_sdk.setAppBackgroundStatus(this, String.valueOf(System.currentTimeMillis()), false);
                Log.i(TAG, "SDK notified: App in foreground");
            } catch (Exception e) {
                Log.e(TAG, "Error setting app background status to false", e);
            }
        }
    }

    @Override
    public void onActivityPaused(@NonNull Activity activity) {
        Log.i(TAG, "onActivityPaused: " + activity.getClass().getSimpleName());

        // Note: Do not immediately set to background here, as other Activities might be
        // starting
        // Real background state is handled in onActivityStopped
    }

    @Override
    public void onActivityStopped(@NonNull Activity activity) {
        Log.i(TAG, "onActivityStopped: " + activity.getClass().getSimpleName());

        // Decrement Activity count
        activityCount--;

        // If all Activities are stopped, app enters background
        if (activityCount <= 0 && isAppInForeground) {
            handleAppBackground();
        }
    }

    @Override
    public void onActivitySaveInstanceState(@NonNull Activity activity, @NonNull Bundle outState) {
        Log.i(TAG, "onActivitySaveInstanceState: " + activity.getClass().getSimpleName());
    }

    @Override
    public void onActivityDestroyed(@NonNull Activity activity) {
        Log.i(TAG, "onActivityDestroyed: " + activity.getClass().getSimpleName());
    }

    /**
     * Handle app entering foreground
     */
    private void handleAppForeground() {
        if (!isAppInForeground) {
            isAppInForeground = true;
            lastForegroundTime = System.currentTimeMillis();

            Log.i(TAG, "App entered foreground");

            // Notify plugin
            if (plugin != null) {
                plugin.handleAppForeground();
            }

            // Calculate background duration
            if (lastBackgroundTime > 0) {
                long backgroundDuration = lastForegroundTime - lastBackgroundTime;
                Log.i(TAG, "App was in background for " + backgroundDuration + "ms");
            }
        }
    }

    /**
     * Handle app entering background
     */
    private void handleAppBackground() {
        if (isAppInForeground) {
            isAppInForeground = false;
            lastBackgroundTime = System.currentTimeMillis();

            Log.i(TAG, "App entered background");

            // Notify plugin
            if (plugin != null) {
                plugin.handleAppBackground();
            }

            // Notify SDK that app is in background
            if (isSDKInitialized) {
                try {
                    Open_im_sdk.setAppBackgroundStatus(this, String.valueOf(System.currentTimeMillis()), true);
                    Log.i(TAG, "SDK notified: App in background");
                } catch (Exception e) {
                    Log.e(TAG, "Error setting app background status to true", e);
                }
            }
        }
    }

    @Override
    public void onError(int i, String s) {
        Log.e(TAG, "SDK Error: " + i + ", Message: " + s);
    }

    @Override
    public void onSuccess(String s) {
        Log.d(TAG, "SDK Success: " + s);
    }

    /**
     * Check if registered
     */
    public boolean isRegistered() {
        return isRegistered;
    }

    /**
     * Check if app is in foreground
     */
    public boolean isAppInForeground() {
        return isAppInForeground;
    }

    /**
     * Get current Activity count
     */
    public int getActivityCount() {
        return activityCount;
    }

    /**
     * Get last foreground time
     */
    public long getLastForegroundTime() {
        return lastForegroundTime;
    }

    /**
     * Get last background time
     */
    public long getLastBackgroundTime() {
        return lastBackgroundTime;
    }
}
