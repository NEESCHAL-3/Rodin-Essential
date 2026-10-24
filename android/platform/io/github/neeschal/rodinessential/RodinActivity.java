package io.github.neeschal.rodinessential;

import android.app.NativeActivity;
import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothA2dp;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import java.util.List;
import android.content.pm.PackageManager;
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
    private boolean audioPermissionPending;
    private BluetoothProfile audioA2dpProxy;
    private boolean audioA2dpRequested;
    private boolean audioReceiverRegistered;
    private final java.util.concurrent.atomic.AtomicInteger
        audioConnectionGeneration =
            new java.util.concurrent.atomic.AtomicInteger();

    private final BroadcastReceiver audioA2dpReceiver =
        new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (BluetoothAdapter.ACTION_STATE_CHANGED.equals(
                        intent.getAction())) {
                    int adapterState = intent.getIntExtra(
                        BluetoothAdapter.EXTRA_STATE,
                        BluetoothAdapter.ERROR
                    );

                    if (adapterState == BluetoothAdapter.STATE_OFF) {
                        clearAudioA2dpProxy();
                    } else if (adapterState == BluetoothAdapter.STATE_ON) {
                        audioRefreshConnectedDevice();
                    }
                    return;
                }

                if (!BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED.equals(
                        intent.getAction())) {
                    return;
                }

                int state = intent.getIntExtra(
                    BluetoothProfile.EXTRA_STATE,
                    BluetoothProfile.STATE_DISCONNECTED
                );

                int previousState = intent.getIntExtra(
                    BluetoothProfile.EXTRA_PREVIOUS_STATE,
                    -1
                );

                android.util.Log.d(
                    "RodinAudioHub",
                    "A2DP transition: previous="
                        + previousState + " current=" + state
                );

                if (previousState == state) {
                    android.util.Log.d(
                        "RodinAudioHub",
                        "Ignoring unchanged A2DP state"
                    );
                    return;
                }

                if (state == BluetoothProfile.STATE_CONNECTED ||
                        state == BluetoothProfile.STATE_DISCONNECTED) {
                    cancelAudioRestore();
                    audioConnectionGeneration.incrementAndGet();
                    audioApplyGeneration.incrementAndGet();
                    audioApplyResult = "DEVICE_CHANGED";
                    audioAppliedDeviceAddress = null;
                    audioAppliedConnectionGeneration = -1;
                    audioConnectedDeviceName = "";
                    audioCodecDiagnosticGeneration.incrementAndGet();
                    audioCodecDiagnosticResult = "NOT_REQUESTED";

                    if (audioA2dpProxy != null) {
                        refreshAudioA2dpDevice();
                    } else {
                        audioRefreshConnectedDevice();
                    }

                    if (state == BluetoothProfile.STATE_CONNECTED
                            && audioRestoreProcessedGeneration
                                != audioConnectionGeneration.get()
                            && audioRestoreManualGeneration
                                != audioConnectionGeneration.get()) {
                        audioRestoreDiscoveryGeneration =
                            audioConnectionGeneration.get();
                        audioRestoreDiscoveryAttempts = 0;

                        audioRestoreDiscoveryTask =
                            RodinActivity.this::discoverAudioRestoreDevice;

                        main.postDelayed(
                            audioRestoreDiscoveryTask,
                            AUDIO_RESTORE_RETRY_DELAY_MS
                        );
                    }
                }
            }
        };
    private volatile String audioConnectedDeviceName = "";
    private volatile String audioCodecDiagnosticResult = "NOT_REQUESTED";
    private volatile String audioApplyResult = "NOT_REQUESTED";
    private final java.util.concurrent.atomic.AtomicInteger
        audioApplyGeneration =
            new java.util.concurrent.atomic.AtomicInteger();
    private String audioAppliedDeviceAddress;
    private int audioAppliedConnectionGeneration = -1;
    private volatile String audioSaveProfileResult = "NOT_REQUESTED";
    private final java.util.concurrent.atomic.AtomicInteger
        audioAutoRestoreGeneration =
            new java.util.concurrent.atomic.AtomicInteger();
    private volatile String audioAutoRestoreResult = "NOT_REQUESTED";

    private Runnable audioRestoreTask;
    private int audioRestoreConnectionGeneration = -1;
    private String audioRestoreDeviceAddress;
    private int audioRestoreRequestFailures;
    private int audioRestoreRequestsSent;
    private int audioRestoreVerificationAttempts;
    private boolean audioRestoreRequestSent;
    private boolean audioRestorePermanentFailure;
    private int audioRestoreProcessedGeneration = -1;
    private volatile int audioRestoreManualGeneration = -1;
    private Runnable audioRestoreDiscoveryTask;
    private int audioRestoreDiscoveryAttempts;
    private int audioRestoreDiscoveryGeneration = -1;
    private static final int AUDIO_RESTORE_DISCOVERY_MAX_ATTEMPTS = 5;
    private static final int AUDIO_RESTORE_MAX_ATTEMPTS = 5;
    private static final long AUDIO_RESTORE_RETRY_DELAY_MS = 1200;

    private volatile String audioDeleteProfileResult = "NOT_REQUESTED";
    private final java.util.concurrent.atomic.AtomicInteger
        audioDeleteProfileGeneration =
            new java.util.concurrent.atomic.AtomicInteger();
    private final java.util.concurrent.atomic.AtomicInteger
        audioSaveProfileGeneration =
            new java.util.concurrent.atomic.AtomicInteger();
    private volatile String audioSavedProfileQueryResult = "NOT_REQUESTED";
    private final java.util.concurrent.atomic.AtomicInteger
        audioSavedProfileGeneration =
            new java.util.concurrent.atomic.AtomicInteger();

    private volatile String audioCompanionStatusResult = "NOT_REQUESTED";
    private static final int AUDIO_COMPANION_REQUEST_CODE = 4108;
    private volatile String audioCompanionAssociationResult = "NOT_REQUESTED";
    private String audioCompanionRequestedAddress;
    private Runnable audioCompanionConfirmationTimeout;

    private final java.util.concurrent.atomic.AtomicInteger
        audioCompanionAssociationGeneration =
            new java.util.concurrent.atomic.AtomicInteger();


    private final java.util.concurrent.atomic.AtomicInteger
        audioCompanionStatusGeneration =
            new java.util.concurrent.atomic.AtomicInteger();

    private final java.util.concurrent.atomic.AtomicInteger audioCodecDiagnosticGeneration = new java.util.concurrent.atomic.AtomicInteger();


    private int audioA2dpGeneration;

    private BluetoothProfile.ServiceListener createAudioA2dpListener(
            final int generation) {
        return new BluetoothProfile.ServiceListener() {
            @Override
            public void onServiceConnected(
                    int profile, BluetoothProfile proxy) {
                if (profile != BluetoothProfile.A2DP) return;

                BluetoothAdapter adapter = null;
                boolean accept = false;

                try {
                    BluetoothManager manager =
                        (BluetoothManager) getSystemService(
                            Context.BLUETOOTH_SERVICE
                        );
                    adapter = manager != null
                        ? manager.getAdapter()
                        : null;

                    accept =
                        generation == audioA2dpGeneration &&
                        !isFinishing() &&
                        !isDestroyed() &&
                        checkSelfPermission(
                            Manifest.permission.BLUETOOTH_CONNECT
                        ) == PackageManager.PERMISSION_GRANTED &&
                        adapter != null &&
                        adapter.isEnabled();

                } catch (RuntimeException exception) {
                    accept = false;
                }

                if (!accept) {
                    if (adapter != null) {
                        try {
                            adapter.closeProfileProxy(
                                BluetoothProfile.A2DP, proxy
                            );
                        } catch (RuntimeException exception) {
                            // Service may already be unavailable.
                        }
                    }
                    return;
                }

                audioA2dpProxy = proxy;
                main.removeCallbacks(audioA2dpRecovery);
                refreshAudioA2dpDevice();
            }

            @Override
            public void onServiceDisconnected(int profile) {
                if (profile != BluetoothProfile.A2DP) return;
                if (generation != audioA2dpGeneration) return;

                cancelAudioRestore();
                audioA2dpGeneration++;
                audioConnectionGeneration.incrementAndGet();
                audioApplyGeneration.incrementAndGet();
                audioApplyResult = "DEVICE_CHANGED";
                audioAppliedDeviceAddress = null;
                audioAppliedConnectionGeneration = -1;
                invalidateAudioCompanionRequestForDeviceChange();
                audioA2dpProxy = null;
                audioActiveDevice = null;
                audioConnectedDeviceName = "";
                audioCodecDiagnosticGeneration.incrementAndGet();
                audioCodecDiagnosticResult = "NOT_REQUESTED";
                audioSavedProfileGeneration.incrementAndGet();
                audioSavedProfileQueryResult = "NOT_REQUESTED";
                audioSaveProfileGeneration.incrementAndGet();
                audioSaveProfileResult = "DEVICE_CHANGED";
                audioDeleteProfileGeneration.incrementAndGet();
                audioDeleteProfileResult = "DEVICE_CHANGED";
                audioA2dpRequested = false;

                main.removeCallbacks(audioA2dpRecovery);

                if (isFinishing() || isDestroyed()) return;

                try {
                    BluetoothManager manager =
                        (BluetoothManager) getSystemService(
                            Context.BLUETOOTH_SERVICE
                        );

                    BluetoothAdapter adapter =
                        manager != null ? manager.getAdapter() : null;

                    if (adapter != null && adapter.isEnabled()) {
                        main.postDelayed(audioA2dpRecovery, 1000);
                    }
                } catch (RuntimeException exception) {
                    // Bluetooth service is unavailable.
                }
            }
        };
    }

    private boolean isAudioRestoreConfigurationActive(
            int codec, int sampleRate, int bits, int ldacQuality) {
        String diagnostic = readAudioCodecStatusDiagnostic();

        if (!diagnostic.startsWith("OK;")) return false;

        int actualCodec = -1;
        int actualRate = -1;
        int actualBits = -1;
        long actualCodecSpecific1 = -1;

        for (String part : diagnostic.split(";")) {
            try {
                if (part.startsWith("codec=")) {
                    actualCodec = Integer.parseInt(part.substring(6));
                } else if (part.startsWith("sampleRate=")) {
                    actualRate = Integer.parseInt(part.substring(11));
                } else if (part.startsWith("bits=")) {
                    actualBits = Integer.parseInt(part.substring(5));
                } else if (part.startsWith("codecSpecific1=")) {
                    actualCodecSpecific1 =
                        Long.parseLong(part.substring(15));
                }
            } catch (NumberFormatException exception) {
                return false;
            }
        }

        return actualCodec == codec
            && actualRate == sampleRate
            && actualBits == bits
            && (ldacQuality == -1
                || (codec == 4
                    && actualCodecSpecific1 == ldacQuality));
    }

    private boolean isAudioRestoreRetryableError(String result) {
        return "A2DP_UNAVAILABLE".equals(result)
            || "DEVICE_UNAVAILABLE".equals(result)
            || "CODEC_STATUS_UNAVAILABLE".equals(result)
            || "CODEC_CONFIG_UNAVAILABLE".equals(result)
            || "CAPABILITIES_UNAVAILABLE".equals(result);
    }

    private boolean requestAudioRestoreConfiguration(
            int codec, int sampleRate, int bits, int ldacQuality) {
        if (audioRestoreRequestSent) return false;

        String result = applyAudioCodecPreference(
            codec, sampleRate, bits, ldacQuality);

        if (!"REQUEST_SENT".equals(result)) {
            android.util.Log.w(
                "RodinAudioHub",
                "Auto Restore request failed: " + result
            );

            audioRestorePermanentFailure =
                !isAudioRestoreRetryableError(result);

            return false;
        }

        audioRestoreRequestSent = true;

        android.util.Log.i(
            "RodinAudioHub",
            "Auto Restore codec preference requested"
        );

        return true;
    }

    private void runAudioRestore() {
        audioRestoreTask = null;

        final int generation = audioConnectionGeneration.get();

        if (generation != audioRestoreConnectionGeneration
                || generation == audioRestoreManualGeneration
                || audioRestoreDeviceAddress == null
                || audioActiveDevice == null
                || audioA2dpProxy == null
                || isFinishing()
                || isDestroyed()) {
            return;
        }

        final String address = audioActiveDevice.getAddress();

        if (!audioRestoreDeviceAddress.equalsIgnoreCase(address)) {
            cancelAudioRestore();
            return;
        }

        try {
            java.lang.reflect.Method activeMethod =
                audioA2dpProxy.getClass().getDeclaredMethod(
                    "getActiveDevice"
                );

            Object active = activeMethod.invoke(audioA2dpProxy);

            if (!(active instanceof BluetoothDevice)
                    || !audioActiveDevice.equals(active)) {
                cancelAudioRestore();
                return;
            }
        } catch (ReflectiveOperationException |
                 SecurityException exception) {
            cancelAudioRestore();
            return;
        }

        org.json.JSONObject profile =
            AudioProfileStore.load(this, address);

        if (profile == null
                || !profile.optBoolean("autoRestore", false)) {
            cancelAudioRestore();
            return;
        }

        final int codec = profile.optInt("codec", -1);
        final int sampleRate = profile.optInt("sampleRate", -1);
        final int bits = profile.optInt("bits", -1);
        final int ldacQuality =
            profile.optInt("version", 1) == 2
                ? profile.optInt("ldacQuality", -1)
                : -1;

        if (codec < 0 || sampleRate <= 0 || bits <= 0) {
            android.util.Log.w(
                "RodinAudioHub",
                "Auto Restore profile contains invalid values"
            );
            cancelAudioRestore();
            return;
        }

        if (isAudioRestoreConfigurationActive(
                codec, sampleRate, bits, ldacQuality)) {
            android.util.Log.i(
                "RodinAudioHub",
                "Auto Restore verified successfully"
            );
            cancelAudioRestore();
            return;
        }

        if (!audioRestoreRequestSent) {
            if (!requestAudioRestoreConfiguration(
                    codec, sampleRate, bits, ldacQuality)) {
                if (audioRestorePermanentFailure) {
                    android.util.Log.w(
                        "RodinAudioHub",
                        "Auto Restore stopped: permanent request failure"
                    );
                    cancelAudioRestore();
                    return;
                }

                audioRestoreRequestFailures++;

                if (audioRestoreRequestFailures
                        >= AUDIO_RESTORE_MAX_ATTEMPTS) {
                    android.util.Log.w(
                        "RodinAudioHub",
                        "Auto Restore request retries exhausted"
                    );
                    cancelAudioRestore();
                    return;
                }

                audioRestoreTask = this::runAudioRestore;
                main.postDelayed(
                    audioRestoreTask,
                    AUDIO_RESTORE_RETRY_DELAY_MS
                );
                return;
            }

            audioRestoreRequestsSent++;
            audioRestoreRequestFailures = 0;
            audioRestoreVerificationAttempts = 0;
        }

        audioRestoreVerificationAttempts++;

        if (audioRestoreVerificationAttempts >= 3) {
            if (audioRestoreRequestsSent >= 2) {
                android.util.Log.w(
                    "RodinAudioHub",
                    "Auto Restore could not verify codec negotiation"
                );
                cancelAudioRestore();
                return;
            }

            android.util.Log.w(
                "RodinAudioHub",
                "Auto Restore negotiation not verified; retrying request"
            );
            audioRestoreRequestSent = false;
            audioRestoreVerificationAttempts = 0;
        }

        audioRestoreTask = this::runAudioRestore;
        main.postDelayed(
            audioRestoreTask,
            AUDIO_RESTORE_RETRY_DELAY_MS
        );
    }

    private void scheduleAudioRestore() {
        if (isFinishing() || isDestroyed()) return;
        if (audioA2dpProxy == null || audioActiveDevice == null) return;

        final int generation = audioConnectionGeneration.get();

        if (audioRestoreManualGeneration == generation
                || audioRestoreProcessedGeneration == generation) {
            return;
        }

        final String address = audioActiveDevice.getAddress();
        if (address == null
                || !BluetoothAdapter.checkBluetoothAddress(address)) {
            return;
        }

        try {
            java.lang.reflect.Method activeMethod =
                audioA2dpProxy.getClass().getDeclaredMethod(
                    "getActiveDevice"
                );

            Object active = activeMethod.invoke(audioA2dpProxy);

            if (!(active instanceof BluetoothDevice)
                    || !audioActiveDevice.equals(active)) {
                return;
            }
        } catch (ReflectiveOperationException |
                 SecurityException exception) {
            return;
        }

        if (audioRestoreConnectionGeneration == generation
                && address.equalsIgnoreCase(audioRestoreDeviceAddress)) {
            return;
        }

        org.json.JSONObject profile =
            AudioProfileStore.load(this, address);

        if (profile == null
                || !profile.optBoolean("autoRestore", false)) {
            return;
        }

        cancelAudioRestore();

        audioRestoreProcessedGeneration = generation;
        audioRestoreConnectionGeneration = generation;
        audioRestoreDeviceAddress = address;
        audioRestoreRequestFailures = 0;
        audioRestoreRequestsSent = 0;
        audioRestoreVerificationAttempts = 0;
        audioRestoreRequestSent = false;

        android.util.Log.i(
            "RodinAudioHub",
            "Auto Restore scheduled for connected A2DP device"
        );

        audioRestoreTask = this::runAudioRestore;
        main.postDelayed(
            audioRestoreTask,
            AUDIO_RESTORE_RETRY_DELAY_MS
        );
    }

    private void discoverAudioRestoreDevice() {
        audioRestoreDiscoveryTask = null;

        if (isFinishing() || isDestroyed()) {
            return;
        }

        final int generation = audioConnectionGeneration.get();

        if (generation != audioRestoreDiscoveryGeneration
                || generation == audioRestoreManualGeneration
                || generation == audioRestoreProcessedGeneration) {
            return;
        }

        if (audioA2dpProxy != null) {
            refreshAudioA2dpDevice(false);

            if (audioRestoreProcessedGeneration == generation) {
                return;
            }
        }

        audioRestoreDiscoveryAttempts++;

        if (audioRestoreDiscoveryAttempts
                >= AUDIO_RESTORE_DISCOVERY_MAX_ATTEMPTS) {
            android.util.Log.w(
                "RodinAudioHub",
                "Auto Restore discovery timed out"
            );
            return;
        }

        audioRestoreDiscoveryTask = this::discoverAudioRestoreDevice;

        main.postDelayed(
            audioRestoreDiscoveryTask,
            AUDIO_RESTORE_RETRY_DELAY_MS
        );
    }

    private void cancelAudioRestore() {
        if (audioRestoreTask != null) {
            main.removeCallbacks(audioRestoreTask);
            audioRestoreTask = null;
        }

        if (audioRestoreDiscoveryTask != null) {
            main.removeCallbacks(audioRestoreDiscoveryTask);
            audioRestoreDiscoveryTask = null;
        }

        audioRestoreDiscoveryAttempts = 0;
        audioRestoreDiscoveryGeneration = -1;
        audioRestoreConnectionGeneration = -1;
        audioRestoreDeviceAddress = null;
        audioRestoreRequestFailures = 0;
        audioRestoreRequestsSent = 0;
        audioRestoreVerificationAttempts = 0;
        audioRestoreRequestSent = false;
        audioRestorePermanentFailure = false;
    }

    private void clearAudioA2dpProxy() {
        cancelAudioRestore();
        main.removeCallbacks(audioA2dpRecovery);
        invalidateAudioCompanionRequestForDeviceChange();
        audioA2dpGeneration++;
        audioConnectionGeneration.incrementAndGet();
        audioApplyGeneration.incrementAndGet();
        audioApplyResult = "DEVICE_CHANGED";
        audioAppliedDeviceAddress = null;
        audioAppliedConnectionGeneration = -1;

        BluetoothProfile proxy = audioA2dpProxy;
        audioA2dpProxy = null;
        audioA2dpRequested = false;
        audioActiveDevice = null;
        audioConnectedDeviceName = "";
        audioCodecDiagnosticGeneration.incrementAndGet();
        audioCodecDiagnosticResult = "NOT_REQUESTED";
        audioSavedProfileGeneration.incrementAndGet();
        audioSavedProfileQueryResult = "NOT_REQUESTED";
        audioSaveProfileGeneration.incrementAndGet();
        audioSaveProfileResult = "DEVICE_CHANGED";
        audioDeleteProfileGeneration.incrementAndGet();
        audioDeleteProfileResult = "DEVICE_CHANGED";

        if (proxy == null) return;

        try {
            BluetoothManager manager =
                (BluetoothManager) getSystemService(
                    Context.BLUETOOTH_SERVICE
                );

            BluetoothAdapter adapter =
                manager != null ? manager.getAdapter() : null;

            if (adapter != null) {
                adapter.closeProfileProxy(
                    BluetoothProfile.A2DP, proxy
                );
            }
        } catch (RuntimeException exception) {
            // Bluetooth service may already be shutting down.
        }
    }

    private final Runnable audioA2dpRecovery = () -> {
        if (isFinishing() || isDestroyed()) return;
        if (audioA2dpProxy != null || audioA2dpRequested) return;

        audioRefreshConnectedDevice();
    };

    private static volatile int audioPermissionGeneration;
    private static native boolean nativeInterceptBack();
    private static native void nativeBack(int phase, float progress, int edge);
    private static native void nativeOpenBypassSettings();

    @Override protected void onCreate(Bundle state) {
        current = this;
        super.onCreate(state);

        IntentFilter audioFilter = new IntentFilter(
            BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED
        );
        audioFilter.addAction(BluetoothAdapter.ACTION_STATE_CHANGED);

        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(
                audioA2dpReceiver,
                audioFilter,
                Context.RECEIVER_EXPORTED
            );
        } else {
            registerReceiver(audioA2dpReceiver, audioFilter);
        }
        audioReceiverRegistered = true;

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
    static boolean isAudioRestoreOwnerActive() {
        RodinActivity activity = current;

        return activity != null
                && !activity.isFinishing()
                && !activity.isDestroyed();
    }

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
        main.removeCallbacks(audioA2dpRecovery);
        audioCodecDiagnosticGeneration.incrementAndGet();
        audioCodecDiagnosticResult = "ACTIVITY_UNAVAILABLE";
        audioSavedProfileGeneration.incrementAndGet();
        audioSavedProfileQueryResult = "ACTIVITY_UNAVAILABLE";
        audioSaveProfileGeneration.incrementAndGet();
        audioSaveProfileResult = "ACTIVITY_UNAVAILABLE";
        audioDeleteProfileGeneration.incrementAndGet();
        audioDeleteProfileResult = "ACTIVITY_UNAVAILABLE";
        audioPermissionPending = false;
        audioCompanionStatusGeneration.incrementAndGet();
        audioCompanionStatusResult = "ACTIVITY_UNAVAILABLE";
        audioCompanionAssociationGeneration.incrementAndGet();
        audioCompanionRequestedAddress = null;
        if (audioCompanionConfirmationTimeout != null) {
            main.removeCallbacks(audioCompanionConfirmationTimeout);
            audioCompanionConfirmationTimeout = null;
        }
        audioCompanionAssociationResult = "ACTIVITY_UNAVAILABLE";

        if (audioReceiverRegistered) {
            unregisterReceiver(audioA2dpReceiver);
            audioReceiverRegistered = false;
        }

        clearAudioA2dpProxy();

        if (current == this) current = null;
        super.onDestroy();
    }


    @Override
    protected void onActivityResult(
            int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode != AUDIO_COMPANION_REQUEST_CODE) return;

        String requestedAddress = audioCompanionRequestedAddress;

        if (requestedAddress == null) {
            return;
        }

        if ("ASSOCIATED".equals(audioCompanionAssociationResult)) {
            audioCompanionAssociationGeneration.incrementAndGet();
            audioCompanionRequestedAddress = null;
            return;
        }

        if (resultCode != RESULT_OK) {
            audioCompanionAssociationGeneration.incrementAndGet();
            audioCompanionRequestedAddress = null;

            if (audioCompanionConfirmationTimeout != null) {
                main.removeCallbacks(audioCompanionConfirmationTimeout);
                audioCompanionConfirmationTimeout = null;
            }

            audioCompanionAssociationResult = "CANCELLED";
            return;
        }

        android.companion.CompanionDeviceManager manager =
            (android.companion.CompanionDeviceManager)
                getSystemService(Context.COMPANION_DEVICE_SERVICE);

        if (manager == null) {
            audioCompanionAssociationGeneration.incrementAndGet();
            audioCompanionRequestedAddress = null;
            audioCompanionAssociationResult = "CDM_UNAVAILABLE";
            return;
        }

        try {
            boolean associated = false;

            for (android.companion.AssociationInfo association
                    : manager.getMyAssociations()) {
                android.net.MacAddress address =
                    association.getDeviceMacAddress();

                if (address != null &&
                        address.toString().equalsIgnoreCase(
                            requestedAddress)) {
                    associated = true;
                    break;
                }
            }

            if (associated) {
                audioCompanionAssociationGeneration.incrementAndGet();
                audioCompanionRequestedAddress = null;
                audioCompanionAssociationResult = "ASSOCIATED";
                audioCompanionStatusGeneration.incrementAndGet();
                audioCompanionStatusResult = "ASSOCIATED";
                registerAudioPresenceIfEnabled(requestedAddress);
            } else {
                // Allow Android to finish creating the association.
                audioCompanionAssociationResult = "AWAITING_CONFIRMATION";
                audioCompanionStatusResult = "NOT_REQUESTED";

                final int generation =
                    audioCompanionAssociationGeneration.get();
                final String expectedAddress = requestedAddress;

                if (audioCompanionConfirmationTimeout != null) {
                    main.removeCallbacks(audioCompanionConfirmationTimeout);
                }

                audioCompanionConfirmationTimeout = () -> {
                    if (current != this || isFinishing() || isDestroyed() ||
                            generation !=
                                audioCompanionAssociationGeneration.get() ||
                            !expectedAddress.equalsIgnoreCase(
                                audioCompanionRequestedAddress == null
                                    ? "" : audioCompanionRequestedAddress)) {
                        return;
                    }

                    boolean confirmed = false;

                    try {
                        android.companion.CompanionDeviceManager cdm =
                            (android.companion.CompanionDeviceManager)
                                getSystemService(
                                    Context.COMPANION_DEVICE_SERVICE);

                        if (cdm != null) {
                            for (android.companion.AssociationInfo info
                                    : cdm.getMyAssociations()) {
                                android.net.MacAddress mac =
                                    info.getDeviceMacAddress();

                                if (mac != null &&
                                        expectedAddress.equalsIgnoreCase(
                                            mac.toString())) {
                                    confirmed = true;
                                    break;
                                }
                            }
                        }
                    } catch (RuntimeException exception) {
                        audioCompanionAssociationResult = "CDM_ERROR";
                    }

                    if (confirmed) {
                        audioCompanionAssociationResult = "ASSOCIATED";
                        audioCompanionStatusGeneration.incrementAndGet();
                        audioCompanionStatusResult = "ASSOCIATED";
                        registerAudioPresenceIfEnabled(requestedAddress);
                    } else if (!"CDM_ERROR".equals(
                            audioCompanionAssociationResult)) {
                        audioCompanionAssociationResult = "NOT_CONFIRMED";
                        audioCompanionStatusResult = "NOT_REQUESTED";
                    }

                    audioCompanionAssociationGeneration.incrementAndGet();
                    audioCompanionRequestedAddress = null;
                    audioCompanionConfirmationTimeout = null;
                };

                if (!main.postDelayed(
                        audioCompanionConfirmationTimeout, 5000L)) {
                    audioCompanionAssociationGeneration.incrementAndGet();
                    audioCompanionRequestedAddress = null;
                    audioCompanionConfirmationTimeout = null;
                    audioCompanionAssociationResult = "POST_FAILED";
                }
            }

        } catch (RuntimeException exception) {
            audioCompanionAssociationGeneration.incrementAndGet();
            audioCompanionRequestedAddress = null;
            audioCompanionAssociationResult = "CDM_ERROR";
        }
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            String[] permissions,
            int[] grantResults) {
        super.onRequestPermissionsResult(
            requestCode, permissions, grantResults);

        if (requestCode == 4107) {
            audioPermissionPending = false;
            audioPermissionGeneration++;
        }
    }

    public static int audioPermissionGeneration() {
        return audioPermissionGeneration;
    }

    /**
     * Bluetooth status:
     * 0 = unavailable
     * 1 = disabled
     * 2 = permission required
     * 3 = enabled and authorized
     */
    public static int audioBluetoothStatus() {
        RodinActivity activity = current;
        if (activity == null) return 0;

        BluetoothManager manager =
            (BluetoothManager) activity.getSystemService(BLUETOOTH_SERVICE);

        if (manager == null) return 0;

        BluetoothAdapter adapter = manager.getAdapter();
        if (adapter == null) return 0;

        if (activity.checkSelfPermission(
                Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return 2;
        }

        try {
            return adapter.isEnabled() ? 3 : 1;
        } catch (SecurityException exception) {
            return 2;
        }
    }


    /**
     * Requests Bluetooth access only after explicit user interaction.
     * Returns 1 if the request was dispatched, otherwise 0.
     */
    public static int requestAudioBluetoothPermission() {
        RodinActivity activity = current;
        if (activity == null) return 0;

        activity.main.post(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) return;

            if (activity.audioPermissionPending) return;

            if (activity.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_CONNECT)
                    != PackageManager.PERMISSION_GRANTED) {
                activity.audioPermissionPending = true;
                try {
                    activity.requestPermissions(
                        new String[] {
                            Manifest.permission.BLUETOOTH_CONNECT
                        },
                        4107
                    );
                } catch (RuntimeException exception) {
                    activity.audioPermissionPending = false;
                    audioPermissionGeneration++;
                }
            }
        });

        return 1;
    }


    /**
     * Read-only Companion Device Manager association status
     * for the currently selected A2DP device.
     */
    public static String audioCompanionAssociationStatus() {
        RodinActivity activity = current;

        if (activity == null ||
                activity.isFinishing() ||
                activity.isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        if (activity.checkSelfPermission(
                Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        BluetoothDevice device = activity.audioActiveDevice;
        if (device == null) return "DEVICE_UNAVAILABLE";

        android.companion.CompanionDeviceManager manager =
            (android.companion.CompanionDeviceManager)
                activity.getSystemService(Context.COMPANION_DEVICE_SERVICE);

        if (manager == null) return "CDM_UNAVAILABLE";

        try {
            String address = device.getAddress();

            for (android.companion.AssociationInfo association
                    : manager.getMyAssociations()) {
                android.net.MacAddress associatedAddress =
                    association.getDeviceMacAddress();

                if (associatedAddress != null &&
                        associatedAddress.toString()
                            .equalsIgnoreCase(address)) {
                    return "ASSOCIATED";
                }
            }

            return "NOT_ASSOCIATED";

        } catch (SecurityException exception) {
            return "CDM_ERROR";
        } catch (RuntimeException exception) {
            return "CDM_ERROR";
        }
    }


    /**
     * Request a read-only CDM association check on Android's main thread.
     */
    public static int audioRequestCompanionAssociationStatus() {
        RodinActivity activity = current;

        if (activity == null ||
                activity.isFinishing() ||
                activity.isDestroyed()) {
            return 0;
        }

        final int generation =
            activity.audioCompanionStatusGeneration.incrementAndGet();

        activity.audioCompanionStatusResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current ||
                    activity.isFinishing() ||
                    activity.isDestroyed() ||
                    generation !=
                        activity.audioCompanionStatusGeneration.get()) {
                return;
            }

            activity.audioCompanionStatusResult =
                audioCompanionAssociationStatus();
        });

        if (!posted) {
            activity.audioCompanionStatusResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }


    /**
     * Starts Android's official companion-device association flow.
     * Must be called on the Android main thread after user interaction.
     */
    private String requestCompanionAssociationOnMain() {
        if (isFinishing() || isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        if (audioCompanionRequestedAddress != null) {
            return "ALREADY_PENDING";
        }

        String status = audioCompanionAssociationStatus();
        if (!"NOT_ASSOCIATED".equals(status)) {
            return status;
        }

        BluetoothDevice device = audioActiveDevice;
        if (device == null) return "DEVICE_UNAVAILABLE";

        BluetoothProfile proxy = audioA2dpProxy;
        if (proxy == null) return "A2DP_UNAVAILABLE";

        try {
            java.lang.reflect.Method activeMethod = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");

            Object active = activeMethod.invoke(proxy);

            if (!(active instanceof BluetoothDevice) ||
                    !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }
        } catch (ReflectiveOperationException |
                 SecurityException exception) {
            return "ACTIVE_DEVICE_UNVERIFIED";
        }

        android.companion.CompanionDeviceManager manager =
            (android.companion.CompanionDeviceManager)
                getSystemService(Context.COMPANION_DEVICE_SERVICE);

        if (manager == null) return "CDM_UNAVAILABLE";

        final String address;

        try {
            address = device.getAddress();

            android.companion.BluetoothDeviceFilter filter =
                new android.companion.BluetoothDeviceFilter.Builder()
                    .setAddress(address)
                    .build();

            android.companion.AssociationRequest request =
                new android.companion.AssociationRequest.Builder()
                    .addDeviceFilter(filter)
                    .setSingleDevice(true)
                    .build();

            if (audioCompanionConfirmationTimeout != null) {
                main.removeCallbacks(audioCompanionConfirmationTimeout);
                audioCompanionConfirmationTimeout = null;
            }

            final int requestGeneration =
                audioCompanionAssociationGeneration.incrementAndGet();

            audioCompanionRequestedAddress = address;
            audioCompanionAssociationResult = "REQUEST_STARTED";

            manager.associate(
                request,
                getMainExecutor(),
                new android.companion.CompanionDeviceManager.Callback() {
                    private boolean isCurrentRequest() {
                        return RodinActivity.current == RodinActivity.this &&
                            !isFinishing() &&
                            !isDestroyed() &&
                            requestGeneration ==
                                audioCompanionAssociationGeneration.get() &&
                            address.equalsIgnoreCase(
                                audioCompanionRequestedAddress == null
                                    ? ""
                                    : audioCompanionRequestedAddress
                            );
                    }

                    @Override
                    public void onAssociationPending(
                            android.content.IntentSender intentSender) {
                        if (!isCurrentRequest()) return;

                        try {
                            startIntentSenderForResult(
                                intentSender,
                                AUDIO_COMPANION_REQUEST_CODE,
                                null,
                                0,
                                0,
                                0
                            );
                            audioCompanionAssociationResult =
                                "WAITING_FOR_USER";
                        } catch (android.content.IntentSender
                                .SendIntentException exception) {
                            audioCompanionAssociationGeneration
                                .incrementAndGet();
                            audioCompanionRequestedAddress = null;
                            audioCompanionAssociationResult =
                                "LAUNCH_FAILED";
                        }
                    }

                    @Override
                    public void onAssociationCreated(
                            android.companion.AssociationInfo association) {
                        if (!isCurrentRequest()) return;

                        String requestedAddress =
                            audioCompanionRequestedAddress;

                        if (requestedAddress == null ||
                                association == null) {
                            invalidateAudioCompanionRequestForDeviceChange();
                            return;
                        }

                        android.net.MacAddress associatedAddress =
                            association.getDeviceMacAddress();

                        if (associatedAddress == null ||
                                !associatedAddress.toString()
                                    .equalsIgnoreCase(requestedAddress)) {
                            invalidateAudioCompanionRequestForDeviceChange();
                            audioCompanionAssociationResult =
                                "DEVICE_MISMATCH";
                            return;
                        }

                        audioCompanionAssociationResult = "ASSOCIATED";
                        audioCompanionStatusGeneration.incrementAndGet();
                        audioCompanionStatusResult = "ASSOCIATED";
                        registerAudioPresenceIfEnabled(requestedAddress);

                        // Complete this request and reject late callbacks.
                        if (audioCompanionConfirmationTimeout != null) {
                            main.removeCallbacks(
                                audioCompanionConfirmationTimeout);
                            audioCompanionConfirmationTimeout = null;
                        }
                        audioCompanionAssociationGeneration.incrementAndGet();
                        audioCompanionRequestedAddress = null;
                    }

                    @Override
                    public void onFailure(
                            CharSequence error) {
                        if (!isCurrentRequest()) return;
                        audioCompanionAssociationGeneration.incrementAndGet();
                        audioCompanionRequestedAddress = null;
                        audioCompanionAssociationResult =
                            "ASSOCIATION_FAILED";
                    }
                }
            );

            return "REQUEST_STARTED";

        } catch (SecurityException exception) {
            audioCompanionAssociationGeneration.incrementAndGet();
            audioCompanionRequestedAddress = null;
            audioCompanionAssociationResult = "PERMISSION_REQUIRED";
            return "PERMISSION_REQUIRED";
        } catch (RuntimeException exception) {
            android.util.Log.e(
                "RodinAudioHub",
                "CDM association request failed",
                exception
            );
            audioCompanionAssociationGeneration.incrementAndGet();
            audioCompanionRequestedAddress = null;
            audioCompanionAssociationResult = "CDM_ERROR";
            return "CDM_ERROR";
        }
    }

    /**
     * Starts the official CDM authorization flow on Android's main thread.
     * This method only schedules the request; it does not grant access.
     */
    public static int audioRequestCompanionAssociation() {
        RodinActivity activity = current;

        if (activity == null ||
                activity.isFinishing() ||
                activity.isDestroyed()) {
            return 0;
        }

        // Reserve the request before posting to prevent duplicate calls.
        final int generation;

        synchronized (activity.audioCompanionAssociationGeneration) {
            String state = activity.audioCompanionAssociationResult;

            if ("PENDING".equals(state) ||
                    "REQUEST_STARTED".equals(state) ||
                    "WAITING_FOR_USER".equals(state) ||
                    "AWAITING_CONFIRMATION".equals(state)) {
                return 0;
            }

            activity.audioCompanionAssociationResult = "PENDING";
            generation =
                activity.audioCompanionAssociationGeneration.incrementAndGet();
        }

        boolean posted = activity.main.post(() -> {
            if (activity != current ||
                    activity.isFinishing() ||
                    activity.isDestroyed()) {
                activity.audioCompanionAssociationResult =
                    "ACTIVITY_UNAVAILABLE";
                return;
            }

            if (generation !=
                    activity.audioCompanionAssociationGeneration.get() ||
                    !"PENDING".equals(
                        activity.audioCompanionAssociationResult)) {
                return;
            }

            String result =
                activity.requestCompanionAssociationOnMain();

            // Do not overwrite a newer Android callback result.
            if ("PENDING".equals(
                    activity.audioCompanionAssociationResult)) {
                activity.audioCompanionAssociationResult = result;
            }
        });

        if (!posted) {
            activity.audioCompanionAssociationResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    /** Latest result of the user-initiated CDM authorization flow. */
    public static String audioCompanionAssociationResult() {
        RodinActivity activity = current;

        return activity != null
            ? activity.audioCompanionAssociationResult
            : "ACTIVITY_UNAVAILABLE";
    }


    /** Latest read-only CDM association result. */
    public static String audioCompanionAssociationStatusResult() {
        RodinActivity activity = current;
        return activity != null
            ? activity.audioCompanionStatusResult
            : "ACTIVITY_UNAVAILABLE";
    }

    public static int audioConnectionGeneration() {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()) {
            return -1;
        }

        return activity.audioConnectionGeneration.get();
    }

    public static String audioConnectedDeviceName() {
        RodinActivity activity = current;
        if (activity == null) return "";
        return activity.audioConnectedDeviceName;
    }

    public static String audioConnectedDeviceAddress() {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()
                || activity.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_CONNECT)
                    != PackageManager.PERMISSION_GRANTED) {
            return "";
        }

        BluetoothDevice device = activity.audioActiveDevice;
        if (device == null) return "";

        String address = device.getAddress();

        return address != null
                && android.bluetooth.BluetoothAdapter
                    .checkBluetoothAddress(address)
            ? address
            : "";
    }

    public static int audioRefreshConnectedDevice() {
        RodinActivity activity = current;
        if (activity == null) return 0;

        activity.audioConnectedDeviceName = "";

        activity.main.post(() -> {
            if (activity.isFinishing() || activity.isDestroyed()) return;

            if (activity.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_CONNECT)
                    != PackageManager.PERMISSION_GRANTED) {
                activity.audioConnectedDeviceName = "";
                return;
            }

            BluetoothManager manager =
                (BluetoothManager) activity.getSystemService(
                    Context.BLUETOOTH_SERVICE);

            if (manager == null || manager.getAdapter() == null) return;

            BluetoothAdapter adapter = manager.getAdapter();

            if (!adapter.isEnabled()) {
                activity.audioConnectedDeviceName = "";
                return;
            }

            if (activity.audioA2dpProxy != null) {
                activity.refreshAudioA2dpDevice();
                return;
            }

            if (!activity.audioA2dpRequested) {
                try {
                    final int generation =
                        ++activity.audioA2dpGeneration;

                    activity.audioA2dpRequested = adapter.getProfileProxy(
                        activity,
                        activity.createAudioA2dpListener(generation),
                        BluetoothProfile.A2DP
                    );
                } catch (SecurityException exception) {
                    activity.audioA2dpRequested = false;
                    activity.audioConnectedDeviceName = "";
                }
            }
        });

        return 1;
    }

    private BluetoothDevice audioActiveDevice;

    private void invalidateAudioCompanionRequestForDeviceChange() {
        if (audioCompanionRequestedAddress == null) return;

        audioCompanionAssociationGeneration.incrementAndGet();
        audioCompanionRequestedAddress = null;

        if (audioCompanionConfirmationTimeout != null) {
            main.removeCallbacks(audioCompanionConfirmationTimeout);
            audioCompanionConfirmationTimeout = null;
        }

        audioCompanionAssociationResult = "DEVICE_CHANGED";
    }

    private void invalidateAudioPendingOperations() {
        audioCodecDiagnosticGeneration.incrementAndGet();
        audioCodecDiagnosticResult = "NOT_REQUESTED";
        audioSavedProfileGeneration.incrementAndGet();
        audioSavedProfileQueryResult = "NOT_REQUESTED";
        audioSaveProfileGeneration.incrementAndGet();
        audioSaveProfileResult = "DEVICE_CHANGED";
        audioDeleteProfileGeneration.incrementAndGet();
        audioDeleteProfileResult = "DEVICE_CHANGED";
    }

    private void refreshAudioA2dpDevice() {
        refreshAudioA2dpDevice(true);
    }

    private void refreshAudioA2dpDevice(
            boolean invalidatePendingOperations) {
        final BluetoothDevice previousDevice = audioActiveDevice;

        audioActiveDevice = null;
        audioConnectedDeviceName = "";

        if (invalidatePendingOperations) {
            invalidateAudioPendingOperations();
        }

        if (audioA2dpProxy == null) {
            if (!invalidatePendingOperations && previousDevice != null) {
                invalidateAudioPendingOperations();
            }
            return;
        }

        try {
            List<BluetoothDevice> devices =
                audioA2dpProxy.getConnectedDevices();

            if (devices == null || devices.isEmpty()) {
                if (!invalidatePendingOperations
                        && previousDevice != null) {
                    invalidateAudioPendingOperations();
                }
                invalidateAudioCompanionRequestForDeviceChange();
                return;
            }

            BluetoothDevice selected = null;

            try {
                java.lang.reflect.Method method =
                    audioA2dpProxy.getClass().getDeclaredMethod(
                        "getActiveDevice"
                    );

                selected = (BluetoothDevice) method.invoke(
                    audioA2dpProxy
                );
            } catch (ReflectiveOperationException |
                     SecurityException exception) {
                // Hidden API unavailable or inaccessible.
            }

            if (selected != null &&
                    !devices.contains(selected)) {
                selected = null;
            }

            if (selected == null && devices.size() == 1) {
                selected = devices.get(0);
            }

            if (selected == null) {
                if (!invalidatePendingOperations
                        && previousDevice != null) {
                    invalidateAudioPendingOperations();
                }
                return;
            }

            if (!invalidatePendingOperations
                    && previousDevice != null
                    && !previousDevice.equals(selected)) {
                invalidateAudioPendingOperations();
            }

            audioActiveDevice = selected;

            if (audioCompanionRequestedAddress != null &&
                    !audioCompanionRequestedAddress.equalsIgnoreCase(
                        selected.getAddress())) {
                invalidateAudioCompanionRequestForDeviceChange();
            }

            String name = selected.getName();
            audioConnectedDeviceName =
                name != null && !name.isEmpty()
                    ? name
                    : "Bluetooth audio device";

            scheduleAudioRestore();

        } catch (SecurityException exception) {
            audioActiveDevice = null;
            audioConnectedDeviceName = "";
        }
    }


    /**
     * Read-only A2DP codec diagnostic.
     * Never changes Bluetooth codec preferences.
     */
    private String readAudioCodecStatusDiagnostic() {
        if (isFinishing() || isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        RodinActivity activity = this;

        if (activity.checkSelfPermission(
                Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        BluetoothProfile proxy = activity.audioA2dpProxy;
        if (proxy == null) return "A2DP_UNAVAILABLE";

        BluetoothDevice device = activity.audioActiveDevice;
        if (device == null) return "DEVICE_UNAVAILABLE";

        try {
            java.lang.reflect.Method activeMethod = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");

            Object active = activeMethod.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            java.lang.reflect.Method method =
                proxy.getClass().getDeclaredMethod(
                    "getCodecStatus",
                    BluetoothDevice.class
                );

            Object result = method.invoke(proxy, device);

            if (!(result instanceof android.bluetooth.BluetoothCodecStatus)) {
                return "CODEC_STATUS_UNAVAILABLE";
            }

            android.bluetooth.BluetoothCodecStatus status =
                (android.bluetooth.BluetoothCodecStatus) result;

            android.bluetooth.BluetoothCodecConfig config =
                status.getCodecConfig();

            if (config == null) return "CODEC_CONFIG_UNAVAILABLE";

            StringBuilder diagnostic = new StringBuilder("OK")
                .append(";codec=").append(config.getCodecType())
                .append(";sampleRate=").append(config.getSampleRate())
                .append(";bits=").append(config.getBitsPerSample())
                .append(";channel=").append(config.getChannelMode())
                .append(";codecSpecific1=").append(
                    config.getCodecSpecific1());

            java.util.List<android.bluetooth.BluetoothCodecConfig> capabilities =
                status.getCodecsSelectableCapabilities();

            if (capabilities != null) {
                for (android.bluetooth.BluetoothCodecConfig capability
                        : capabilities) {
                    diagnostic.append(";cap=")
                        .append(capability.getCodecType())
                        .append(",")
                        .append(capability.getSampleRate())
                        .append(",")
                        .append(capability.getBitsPerSample())
                        .append(",")
                        .append(capability.getChannelMode());
                }
            }

            return diagnostic.toString();

        } catch (java.lang.reflect.InvocationTargetException exception) {
            Throwable cause = exception.getCause();
            android.util.Log.e(
                "RodinAudioHub",
                "Bluetooth codec diagnostic invocation failed",
                cause != null ? cause : exception
            );
            return "INVOCATION_ERROR:"
                + (cause != null
                    ? cause.getClass().getSimpleName()
                    : "Unknown");
        } catch (ReflectiveOperationException exception) {
            return "REFLECTION_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (SecurityException exception) {
            return "SECURITY_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (RuntimeException exception) {
            return "RUNTIME_ERROR:"
                + exception.getClass().getSimpleName();
        }
    }

    /**
     * Schedule a read-only codec diagnostic on Android's main thread.
     * Returns 1 when scheduled, 0 when the activity is unavailable.
     */

    private String applyAudioCodecPreference(
            int codecType, int sampleRate, int bitsPerSample) {
        return applyAudioCodecPreference(
            codecType, sampleRate, bitsPerSample, -1);
    }

    private String applyAudioCodecPreference(
            int codecType, int sampleRate, int bitsPerSample,
            int ldacQuality) {
        audioAppliedDeviceAddress = null;
        audioAppliedConnectionGeneration = -1;

        if (isFinishing() || isDestroyed()) return "ACTIVITY_UNAVAILABLE";

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        BluetoothProfile proxy = audioA2dpProxy;
        BluetoothDevice device = audioActiveDevice;

        if (proxy == null) return "A2DP_UNAVAILABLE";
        if (device == null) return "DEVICE_UNAVAILABLE";

        try {
            java.lang.reflect.Method activeMethod = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");
            Object active = activeMethod.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            java.lang.reflect.Method statusMethod = proxy.getClass()
                .getDeclaredMethod("getCodecStatus", BluetoothDevice.class);

            Object result = statusMethod.invoke(proxy, device);

            if (!(result instanceof android.bluetooth.BluetoothCodecStatus)) {
                return "CODEC_STATUS_UNAVAILABLE";
            }

            android.bluetooth.BluetoothCodecStatus status =
                (android.bluetooth.BluetoothCodecStatus) result;

            android.bluetooth.BluetoothCodecConfig currentConfig =
                status.getCodecConfig();

            if (currentConfig == null) return "CODEC_CONFIG_UNAVAILABLE";

            android.bluetooth.BluetoothCodecConfig selectedCapability = null;

            java.util.List<android.bluetooth.BluetoothCodecConfig> capabilities =
                status.getCodecsSelectableCapabilities();

            if (capabilities == null) return "CAPABILITIES_UNAVAILABLE";

            for (android.bluetooth.BluetoothCodecConfig capability
                    : capabilities) {
                if (capability.getCodecType() == codecType
                        && (capability.getSampleRate() & sampleRate) != 0
                        && (capability.getBitsPerSample() & bitsPerSample) != 0) {
                    selectedCapability = capability;
                    break;
                }
            }

            if (selectedCapability == null) return "UNSUPPORTED_SELECTION";

            int channelMode = selectedCapability.getChannelMode()
                & currentConfig.getChannelMode();

            if (channelMode == 0) {
                channelMode = selectedCapability.getChannelMode()
                    & android.bluetooth.BluetoothCodecConfig.CHANNEL_MODE_STEREO;
            }

            if (channelMode == 0) return "CHANNEL_MODE_UNAVAILABLE";

            android.bluetooth.BluetoothCodecConfig.Builder builder =
                new android.bluetooth.BluetoothCodecConfig.Builder()
                    .setCodecType(codecType)
                    .setCodecPriority(
                        android.bluetooth.BluetoothCodecConfig
                            .CODEC_PRIORITY_HIGHEST)
                    .setSampleRate(sampleRate)
                    .setBitsPerSample(bitsPerSample)
                    .setChannelMode(channelMode);

            if (codecType == currentConfig.getCodecType()) {
                builder
                    .setCodecSpecific1(currentConfig.getCodecSpecific1())
                    .setCodecSpecific2(currentConfig.getCodecSpecific2())
                    .setCodecSpecific3(currentConfig.getCodecSpecific3())
                    .setCodecSpecific4(currentConfig.getCodecSpecific4());
            }

            if (codecType == 4 && ldacQuality != -1) {
                if (ldacQuality < 1000 || ldacQuality > 1003) {
                    return "INVALID_LDAC_QUALITY";
                }
                builder.setCodecSpecific1(ldacQuality);
            } else if (codecType != 4 && ldacQuality != -1) {
                return "LDAC_QUALITY_NOT_APPLICABLE";
            }

            android.bluetooth.BluetoothCodecConfig requested = builder.build();

            if (!status.isCodecConfigSelectable(requested)) {
                return "CONFIG_NOT_SELECTABLE";
            }

            java.lang.reflect.Method applyMethod = proxy.getClass()
                .getDeclaredMethod(
                    "setCodecConfigPreference",
                    BluetoothDevice.class,
                    android.bluetooth.BluetoothCodecConfig.class);

            applyMethod.invoke(proxy, device, requested);

            audioAppliedDeviceAddress = device.getAddress();
            audioAppliedConnectionGeneration =
                audioConnectionGeneration.get();

            return "REQUEST_SENT";
        } catch (java.lang.reflect.InvocationTargetException exception) {
            Throwable cause = exception.getCause();
            return "INVOCATION_ERROR:" + (cause != null
                ? cause.getClass().getSimpleName() : "Unknown");
        } catch (ReflectiveOperationException exception) {
            return "REFLECTION_ERROR:" + exception.getClass().getSimpleName();
        } catch (SecurityException exception) {
            return "SECURITY_ERROR:" + exception.getClass().getSimpleName();
        } catch (RuntimeException exception) {
            return "RUNTIME_ERROR:" + exception.getClass().getSimpleName();
        }
    }

    public static String audioApplyCodecPreference(
            int codecType, int sampleRate, int bitsPerSample) {
        RodinActivity activity = current;

        if (activity == null) return "ACTIVITY_UNAVAILABLE";

        if (android.os.Looper.myLooper() != activity.main.getLooper()) {
            return "MAIN_THREAD_REQUIRED";
        }

        return activity.applyAudioCodecPreference(
            codecType, sampleRate, bitsPerSample);
    }


    public static int audioRequestApplyCodecPreference(
            int codecType, int sampleRate, int bitsPerSample) {
        return audioRequestApplyCodecPreference(
            codecType, sampleRate, bitsPerSample, -1);
    }

    public static int audioRequestApplyCodecPreference(
            int codecType, int sampleRate, int bitsPerSample,
            int ldacQuality) {
        RodinActivity activity = current;
        if (activity == null) return 0;

        final int expectedConnectionGeneration =
            activity.audioConnectionGeneration.get();

        activity.audioRestoreManualGeneration =
            expectedConnectionGeneration;

        final int generation =
            activity.audioApplyGeneration.incrementAndGet();

        activity.audioApplyResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current
                    || activity.isFinishing()
                    || activity.isDestroyed()
                    || generation != activity.audioApplyGeneration.get()
                    || expectedConnectionGeneration
                        != activity.audioConnectionGeneration.get()) {
                return;
            }

            activity.cancelAudioRestore();

            activity.audioApplyResult = activity.applyAudioCodecPreference(
                codecType, sampleRate, bitsPerSample, ldacQuality);
        });

        if (!posted) {
            activity.audioApplyResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    public static int audioCancelPendingCodecApply() {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()) {
            return 0;
        }

        activity.audioApplyGeneration.incrementAndGet();
        activity.audioApplyResult = "CANCELLED";
        return 1;
    }

    public static String audioApplyCodecResult() {
        RodinActivity activity = current;
        return activity != null
            ? activity.audioApplyResult
            : "ACTIVITY_UNAVAILABLE";
    }

    public static int audioRequestCodecDiagnostic() {
        RodinActivity activity = current;
        if (activity == null ||
                activity.isFinishing() ||
                activity.isDestroyed()) {
            return 0;
        }

        final int generation =
            activity.audioCodecDiagnosticGeneration.incrementAndGet();
        activity.audioCodecDiagnosticResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current ||
                    activity.isFinishing() ||
                    activity.isDestroyed() ||
                    generation != activity.audioCodecDiagnosticGeneration.get()) {
                return;
            }

            activity.audioCodecDiagnosticResult =
                activity.readAudioCodecStatusDiagnostic();
        });

        if (!posted) {
            activity.audioCodecDiagnosticResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    /** Returns the latest read-only diagnostic snapshot. */
    public static String audioCodecDiagnosticResult() {
        RodinActivity activity = current;
        return activity != null
            ? activity.audioCodecDiagnosticResult
            : "ACTIVITY_UNAVAILABLE";
    }




    public static int audioRequestSavedProfile() {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()) {
            return 0;
        }

        final int generation =
            activity.audioSavedProfileGeneration.incrementAndGet();

        activity.audioSavedProfileQueryResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current
                    || activity.isFinishing()
                    || activity.isDestroyed()
                    || generation != activity.audioSavedProfileGeneration.get()) {
                return;
            }

            activity.audioSavedProfileQueryResult =
                activity.readSavedAudioProfile();
        });

        if (!posted) {
            activity.audioSavedProfileQueryResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    public static String audioSavedProfileQueryResult() {
        RodinActivity activity = current;

        return activity != null
            ? activity.audioSavedProfileQueryResult
            : "ACTIVITY_UNAVAILABLE";
    }

    private String readSavedAudioProfile() {
        if (isFinishing() || isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        BluetoothProfile proxy = audioA2dpProxy;
        BluetoothDevice device = audioActiveDevice;

        if (proxy == null) return "A2DP_UNAVAILABLE";
        if (device == null) return "DEVICE_UNAVAILABLE";

        try {
            java.lang.reflect.Method method = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");

            Object active = method.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            org.json.JSONObject profile =
                AudioProfileStore.load(this, device.getAddress());

            return profile != null
                ? "PROFILE_FOUND;" + profile.toString()
                : "NO_PROFILE";

        } catch (java.lang.reflect.InvocationTargetException exception) {
            Throwable cause = exception.getCause();
            return "INVOCATION_ERROR:" + (cause != null
                ? cause.getClass().getSimpleName() : "Unknown");
        } catch (ReflectiveOperationException exception) {
            return "REFLECTION_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (SecurityException exception) {
            return "SECURITY_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (RuntimeException exception) {
            return "RUNTIME_ERROR:"
                + exception.getClass().getSimpleName();
        }
    }

    public static String audioSavedProfileResult() {
        RodinActivity activity = current;

        if (activity == null) return "ACTIVITY_UNAVAILABLE";

        if (android.os.Looper.myLooper() != activity.main.getLooper()) {
            return "MAIN_THREAD_REQUIRED";
        }

        return activity.readSavedAudioProfile();
    }

    private String saveAudioDeviceProfile(
            int codecType, int sampleRate, int bitsPerSample,
            int expectedConnectionGeneration) {
        return saveAudioDeviceProfile(
            codecType, sampleRate, bitsPerSample,
            -1, expectedConnectionGeneration);
    }

    private String saveAudioDeviceProfile(
            int codecType, int sampleRate, int bitsPerSample,
            int ldacQuality, int expectedConnectionGeneration) {
        if (ldacQuality != -1 &&
                (codecType != 4 ||
                 ldacQuality < 1000 ||
                 ldacQuality > 1003)) {
            return "INVALID_LDAC_QUALITY";
        }

        if (expectedConnectionGeneration < 0 ||
                audioConnectionGeneration.get() !=
                    expectedConnectionGeneration) {
            return "CONNECTION_CHANGED";
        }

        if (isFinishing() || isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        BluetoothProfile proxy = audioA2dpProxy;
        BluetoothDevice device = audioActiveDevice;

        if (proxy == null) return "A2DP_UNAVAILABLE";
        if (device == null) return "DEVICE_UNAVAILABLE";

        if (audioAppliedDeviceAddress == null
                || audioAppliedConnectionGeneration !=
                    expectedConnectionGeneration
                || !audioAppliedDeviceAddress.equalsIgnoreCase(
                    device.getAddress())) {
            return "APPLIED_DEVICE_MISMATCH";
        }

        try {
            java.lang.reflect.Method activeMethod = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");

            Object active = activeMethod.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            java.lang.reflect.Method statusMethod = proxy.getClass()
                .getDeclaredMethod(
                    "getCodecStatus", BluetoothDevice.class);

            Object result = statusMethod.invoke(proxy, device);

            if (!(result instanceof android.bluetooth.BluetoothCodecStatus)) {
                return "CODEC_STATUS_UNAVAILABLE";
            }

            android.bluetooth.BluetoothCodecStatus status =
                (android.bluetooth.BluetoothCodecStatus) result;

            android.bluetooth.BluetoothCodecConfig activeConfig =
                status.getCodecConfig();

            if (activeConfig == null
                    || activeConfig.getCodecType() != codecType
                    || activeConfig.getSampleRate() != sampleRate
                    || activeConfig.getBitsPerSample() != bitsPerSample) {
                return "ACTIVE_CODEC_MISMATCH";
            }

            if (ldacQuality != -1 &&
                    activeConfig.getCodecSpecific1() != ldacQuality) {
                return "ACTIVE_LDAC_QUALITY_MISMATCH";
            }

            java.util.List<android.bluetooth.BluetoothCodecConfig> capabilities =
                status.getCodecsSelectableCapabilities();

            if (capabilities == null) {
                return "CAPABILITIES_UNAVAILABLE";
            }

            boolean supported = false;

            for (android.bluetooth.BluetoothCodecConfig capability
                    : capabilities) {
                if (capability.getCodecType() == codecType
                        && (capability.getSampleRate() & sampleRate) != 0
                        && (capability.getBitsPerSample() & bitsPerSample) != 0) {
                    supported = true;
                    break;
                }
            }

            if (!supported) return "UNSUPPORTED_SELECTION";

            if (audioConnectionGeneration.get() !=
                    expectedConnectionGeneration) {
                return "CONNECTION_CHANGED";
            }

            org.json.JSONObject existingProfile =
                AudioProfileStore.load(this, device.getAddress());

            boolean preserveAutoRestore =
                existingProfile != null
                    && existingProfile.optBoolean("autoRestore", false);

            AudioProfileStore.save(
                this,
                device.getAddress(),
                device.getName(),
                codecType,
                sampleRate,
                bitsPerSample,
                ldacQuality,
                preserveAutoRestore);

            return "PROFILE_SAVED";

        } catch (java.lang.reflect.InvocationTargetException exception) {
            Throwable cause = exception.getCause();
            return "INVOCATION_ERROR:" + (cause != null
                ? cause.getClass().getSimpleName() : "Unknown");
        } catch (ReflectiveOperationException exception) {
            return "REFLECTION_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (SecurityException exception) {
            return "SECURITY_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (RuntimeException exception) {
            return "RUNTIME_ERROR:"
                + exception.getClass().getSimpleName();
        }
    }

    public static int audioRequestSaveDeviceProfile(
            int codecType, int sampleRate, int bitsPerSample,
            int expectedConnectionGeneration) {
        return audioRequestSaveDeviceProfile(
            codecType, sampleRate, bitsPerSample,
            -1, expectedConnectionGeneration);
    }

    public static int audioRequestSaveDeviceProfile(
            int codecType, int sampleRate, int bitsPerSample,
            int ldacQuality, int expectedConnectionGeneration) {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()) {
            return 0;
        }

        final int generation =
            activity.audioSaveProfileGeneration.incrementAndGet();

        activity.audioSaveProfileResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current
                    || activity.isFinishing()
                    || activity.isDestroyed()
                    || generation != activity.audioSaveProfileGeneration.get()) {
                return;
            }

            activity.audioSaveProfileResult =
                activity.saveAudioDeviceProfile(
                    codecType, sampleRate, bitsPerSample,
                    ldacQuality, expectedConnectionGeneration);
        });

        if (!posted) {
            activity.audioSaveProfileResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    public static String audioSaveDeviceProfileResult() {
        RodinActivity activity = current;

        return activity != null
            ? activity.audioSaveProfileResult
            : "ACTIVITY_UNAVAILABLE";
    }


    public static int audioRequestSetAutoRestore(
            int expectedConnectionGeneration,
            boolean enabled,
            String expectedAddress) {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()
                || expectedConnectionGeneration < 0
                || expectedAddress == null
                || !BluetoothAdapter.checkBluetoothAddress(expectedAddress)) {
            return 0;
        }

        final int generation =
            activity.audioAutoRestoreGeneration.incrementAndGet();

        activity.audioAutoRestoreResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current
                    || activity.isFinishing()
                    || activity.isDestroyed()
                    || generation != activity.audioAutoRestoreGeneration.get()) {
                return;
            }

            activity.audioAutoRestoreResult =
                activity.setSavedAudioAutoRestore(
                    expectedConnectionGeneration, expectedAddress, enabled);
        });

        if (!posted) {
            activity.audioAutoRestoreResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    public static String audioAutoRestoreResult() {
        RodinActivity activity = current;
        return activity != null
            ? activity.audioAutoRestoreResult
            : "ACTIVITY_UNAVAILABLE";
    }


    private void registerAudioPresenceIfEnabled(String address) {
        if (address == null) return;

        org.json.JSONObject profile =
            AudioProfileStore.load(this, address);

        if (profile == null ||
                !profile.optBoolean("autoRestore", false)) {
            return;
        }

        String result = AudioPresenceObserver.setObserving(
            this, address, true);

        android.util.Log.i(
            "RodinAudioCDM",
            "ASSOCIATION_OBSERVATION=" + result
        );
    }

    private String setSavedAudioAutoRestore(
            int expectedConnectionGeneration,
            String expectedAddress,
            boolean enabled) {
        if (isFinishing() || isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        if (audioConnectionGeneration.get() !=
                expectedConnectionGeneration) {
            return "CONNECTION_CHANGED";
        }

        BluetoothProfile proxy = audioA2dpProxy;
        BluetoothDevice device = audioActiveDevice;

        if (proxy == null) return "A2DP_UNAVAILABLE";
        if (device == null) return "DEVICE_UNAVAILABLE";

        try {
            String address = device.getAddress();

            if (address == null
                    || !expectedAddress.equalsIgnoreCase(address)) {
                return "DEVICE_CHANGED";
            }

            java.lang.reflect.Method method = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");

            Object active = method.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            if (audioConnectionGeneration.get() !=
                    expectedConnectionGeneration) {
                return "CONNECTION_CHANGED";
            }

            org.json.JSONObject previousProfile =
                AudioProfileStore.load(this, address);

            if (previousProfile == null) {
                return "PROFILE_NOT_FOUND";
            }

            boolean previousEnabled =
                previousProfile.optBoolean("autoRestore", false);

            if (!AudioProfileStore.setAutoRestore(
                    this, address, enabled)) {
                return "PROFILE_UPDATE_FAILED";
            }

            String observationResult =
                AudioPresenceObserver.setObserving(
                    this, address, enabled);

            android.util.Log.i(
                "RodinAudioCDM",
                "AUTO_RESTORE_CDM=" + observationResult
            );

            String expectedObservationResult = enabled
                ? "OBSERVATION_REGISTERED"
                : "OBSERVATION_STOPPED";

            if (!expectedObservationResult.equals(observationResult)) {
                boolean restored = AudioProfileStore.setAutoRestore(
                    this, address, previousEnabled);

                if (!restored) {
                    android.util.Log.e(
                        "RodinAudioCDM",
                        "AUTO_RESTORE_ROLLBACK_FAILED"
                    );
                    return "AUTO_RESTORE_ROLLBACK_FAILED";
                }

                return "CDM_" + observationResult;
            }

            return "AUTO_RESTORE_UPDATED;" + enabled;

        } catch (java.lang.reflect.InvocationTargetException exception) {
            Throwable cause = exception.getCause();
            return "INVOCATION_ERROR:" + (cause != null
                ? cause.getClass().getSimpleName() : "Unknown");
        } catch (ReflectiveOperationException exception) {
            return "REFLECTION_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (SecurityException exception) {
            return "SECURITY_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (RuntimeException exception) {
            return "RUNTIME_ERROR:"
                + exception.getClass().getSimpleName();
        }
    }

    public static int audioRequestDeleteDeviceProfile(
            int expectedConnectionGeneration,
            String expectedAddress) {
        RodinActivity activity = current;

        if (activity == null
                || activity.isFinishing()
                || activity.isDestroyed()) {
            return 0;
        }

        final int generation =
            activity.audioDeleteProfileGeneration.incrementAndGet();

        activity.audioDeleteProfileResult = "PENDING";

        boolean posted = activity.main.post(() -> {
            if (activity != current
                    || activity.isFinishing()
                    || activity.isDestroyed()
                    || generation !=
                        activity.audioDeleteProfileGeneration.get()) {
                return;
            }

            activity.audioDeleteProfileResult =
                activity.deleteSavedAudioProfile(
                    expectedConnectionGeneration,
                    expectedAddress);
        });

        if (!posted) {
            activity.audioDeleteProfileResult = "POST_FAILED";
            return 0;
        }

        return 1;
    }

    public static String audioDeleteDeviceProfileResult() {
        RodinActivity activity = current;

        return activity != null
            ? activity.audioDeleteProfileResult
            : "ACTIVITY_UNAVAILABLE";
    }

    private String deleteSavedAudioProfile(
            int expectedConnectionGeneration,
            String expectedAddress) {
        if (isFinishing() || isDestroyed()) {
            return "ACTIVITY_UNAVAILABLE";
        }

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            return "PERMISSION_REQUIRED";
        }

        if (audioConnectionGeneration.get() !=
                expectedConnectionGeneration) {
            return "CONNECTION_CHANGED";
        }

        if (expectedAddress == null
                || !android.bluetooth.BluetoothAdapter
                    .checkBluetoothAddress(expectedAddress)) {
            return "INVALID_ADDRESS";
        }

        BluetoothProfile proxy = audioA2dpProxy;
        BluetoothDevice device = audioActiveDevice;

        if (proxy == null) return "A2DP_UNAVAILABLE";
        if (device == null) return "DEVICE_UNAVAILABLE";

        try {
            String activeAddress = device.getAddress();
            if (activeAddress == null
                    || !expectedAddress.equalsIgnoreCase(activeAddress)) {
                return "DEVICE_CHANGED";
            }
            java.lang.reflect.Method method = proxy.getClass()
                .getDeclaredMethod("getActiveDevice");

            Object active = method.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            String address = device.getAddress();

            org.json.JSONObject savedProfile =
                AudioProfileStore.load(this, address);

            if (savedProfile == null) {
                return "NO_PROFILE";
            }

            if (audioConnectionGeneration.get() !=
                    expectedConnectionGeneration) {
                return "CONNECTION_CHANGED";
            }

            boolean observing =
                savedProfile.optBoolean("autoRestore", false);

            if (observing) {
                String stopResult =
                    AudioPresenceObserver.setObserving(
                        this, address, false);

                android.util.Log.i(
                    "RodinAudioCDM",
                    "DELETE_PROFILE_STOP_OBSERVATION=" + stopResult
                );

                if (!"OBSERVATION_STOPPED".equals(stopResult)) {
                    return "CDM_STOP_FAILED:" + stopResult;
                }
            }

            if (AudioProfileStore.delete(this, address)) {
                return "PROFILE_DELETED";
            }

            if (observing) {
                String restartResult =
                    AudioPresenceObserver.setObserving(
                        this, address, true);

                android.util.Log.w(
                    "RodinAudioCDM",
                    "DELETE_PROFILE_RESTORE_OBSERVATION=" + restartResult
                );

                if (!"OBSERVATION_REGISTERED".equals(restartResult)) {
                    return "DELETE_FAILED_CDM_RESTORE_FAILED:"
                        + restartResult;
                }
            }

            return "DELETE_FAILED";

        } catch (java.lang.reflect.InvocationTargetException exception) {
            Throwable cause = exception.getCause();
            return "INVOCATION_ERROR:" + (cause != null
                ? cause.getClass().getSimpleName() : "Unknown");
        } catch (ReflectiveOperationException exception) {
            return "REFLECTION_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (SecurityException exception) {
            return "SECURITY_ERROR:"
                + exception.getClass().getSimpleName();
        } catch (RuntimeException exception) {
            return "RUNTIME_ERROR:"
                + exception.getClass().getSimpleName();
        }
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
