package io.github.neeschal.rodinessential;

import android.app.NativeActivity;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.window.BackEvent;
import android.window.OnBackAnimationCallback;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;

/** NEESCHAL: a platform adapter, not a second UI toolkit. */
public final class RodinActivity extends NativeActivity {
    static { System.loadLibrary("rodin_essential_host"); }
    private static RodinActivity current;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable refresh = this::refreshBack;
    private OnBackInvokedCallback callback;
    private boolean registered;
    private boolean resumed;
    private static native boolean nativeInterceptBack();
    private static native void nativeBack(int phase, float progress, int edge);
    private static native void nativeOpenBypassSettings();

    @Override protected void onCreate(Bundle state) {
        current = this;
        super.onCreate(state);
        if (Build.VERSION.SDK_INT >= 34) callback = new ProgressCallback();
        else if (Build.VERSION.SDK_INT >= 33) callback = () -> nativeBack(4, 1, 0);
        handleTileIntent(getIntent());
    }
    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent); setIntent(intent); handleTileIntent(intent);
    }
    private void handleTileIntent(Intent intent) {
        if (intent != null && "android.service.quicksettings.action.QS_TILE_PREFERENCES".equals(intent.getAction()))
            nativeOpenBypassSettings();
    }
    /** Called only when native navigation ownership changes; no polling loop. */
    public static void refreshBackFromNative() {
        RodinActivity activity = current;
        if (activity != null) {
            activity.main.removeCallbacks(activity.refresh);
            activity.main.post(activity.refresh);
        }
    }
    private void refreshBack() {
        if (Build.VERSION.SDK_INT < 33 || callback == null) return;
        boolean wanted = resumed && nativeInterceptBack();
        if (wanted == registered) return;
        if (wanted) getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback);
        else getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(callback);
        registered = wanted;
    }
    @Override protected void onResume() { super.onResume(); resumed = true; refreshBack(); }
    @Override protected void onPause() {
        resumed = false; refreshBack(); nativeBack(3, 0, 0); super.onPause();
    }
    @Override protected void onDestroy() {
        main.removeCallbacks(refresh);
        if (current == this) current = null;
        super.onDestroy();
    }
    // Isolated API-34 class: older devices never instantiate progress callbacks.
    private static final class ProgressCallback implements OnBackAnimationCallback {
        private int edge;
        @Override public void onBackStarted(BackEvent event) {
            edge = event.getSwipeEdge();
            nativeBack(1, event.getProgress(), event.getSwipeEdge());
        }
        @Override public void onBackProgressed(BackEvent event) {
            nativeBack(2, event.getProgress(), event.getSwipeEdge());
        }
        @Override public void onBackCancelled() { nativeBack(3, 0, edge); }
        @Override public void onBackInvoked() { nativeBack(4, 1, edge); }
    }
}
