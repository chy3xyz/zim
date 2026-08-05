package io.openim.flutter_openim_sdk.connectivity;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.os.Build;

import io.flutter.Log;
import open_im_sdk.Open_im_sdk;

/**
 * Fixed network connectivity listener - Improved lifecycle management
 */
public class ConnectivityListener implements open_im_sdk_callback.Base {
    public static final String CONNECTIVITY_ACTION = "android.net.conn.CONNECTIVITY_CHANGE";
    private static final String TAG = "ConnectivityListener";

    private Context context;
    private ConnectivityManager connectivityManager;
    private Connectivity connectivity;
    private ConnectivityBroadcastReceiver receiver;
    private ConnectivityManager.NetworkCallback networkCallback;
    private boolean isRegistered = false;
    private boolean isSDKInitialized = false;

    public ConnectivityListener(Context context) {
        this.context = context;
        this.connectivityManager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        this.connectivity = new Connectivity(connectivityManager);
        this.receiver = new ConnectivityBroadcastReceiver(this);
    }

    /**
     * Set SDK initialization status
     */
    public void setSDKInitialized(boolean initialized) {
        this.isSDKInitialized = initialized;
    }

    private void onChangedNetworkStatus() {
        String status = connectivity.getNetworkType();
        if (Connectivity.CONNECTIVITY_MOBILE.equals(status) || Connectivity.CONNECTIVITY_WIFI.equals(status)) {
            Log.i(TAG, "networkStatusChanged: " + status);

            // Only call network status change when SDK is initialized
            if (isSDKInitialized) {
                try {
                    Open_im_sdk.networkStatusChanged(this, String.valueOf(System.currentTimeMillis()));
                } catch (Exception e) {
                    Log.e(TAG, "Error calling networkStatusChanged", e);
                }
            } else {
                Log.w(TAG, "SDK not initialized, skipping network status change");
            }
        }
    }

    /**
     * Register network status listener
     */
    public void register() {
        if (isRegistered) {
            Log.w(TAG, "Already registered, skipping registration");
            return;
        }

        try {
            if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                networkCallback = new ConnectivityManager.NetworkCallback() {
                    @Override
                    public void onAvailable(Network network) {
                        onChangedNetworkStatus();
                    }

                    @Override
                    public void onLost(Network network) {
                        Log.i(TAG, "Network lost");
                    }
                };
                connectivity.getConnectivityManager().registerDefaultNetworkCallback(networkCallback);
            } else {
                context.registerReceiver(receiver, new IntentFilter(CONNECTIVITY_ACTION));
            }
            isRegistered = true;
            Log.i(TAG, "Network listener registered");
        } catch (Exception e) {
            Log.e(TAG, "Error registering network listener", e);
        }
    }

    /**
     * Unregister network status listener
     */
    public void unregisterReceiver() {
        if (!isRegistered) {
            Log.w(TAG, "Not registered, skipping unregistration");
            return;
        }

        try {
            if (android.os.Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                if (networkCallback != null) {
                    connectivity.getConnectivityManager().unregisterNetworkCallback(networkCallback);
                    networkCallback = null;
                }
            } else {
                if (receiver != null) {
                    context.unregisterReceiver(receiver);
                    receiver = null;
                }
            }
            isRegistered = false;
            Log.i(TAG, "Network listener unregistered");
        } catch (Exception e) {
            Log.e(TAG, "Error unregistering network listener", e);
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
     * Network status change broadcast receiver
     */
    public static class ConnectivityBroadcastReceiver extends BroadcastReceiver {
        private ConnectivityListener listener;

        public ConnectivityBroadcastReceiver(ConnectivityListener listener) {
            this.listener = listener;
        }

        @Override
        public void onReceive(Context context, Intent intent) {
            if (listener != null && CONNECTIVITY_ACTION.equals(intent.getAction())) {
                listener.onChangedNetworkStatus();
            }
        }
    }
}
