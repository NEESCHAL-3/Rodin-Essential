package io.github.neeschal.rodinessential;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothProfile;
import android.companion.AssociationInfo;
import android.companion.CompanionDeviceManager;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import org.json.JSONObject;

import java.util.List;

final class AudioRestoreController {
    private static final String TAG = "RodinAudioRestore";
    private static int activeAssociationId = -1;
    private static Runnable activeCancellation;
    private static final Handler MAIN =
            new Handler(Looper.getMainLooper());

    private static void onMain(Runnable operation) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            operation.run();
        } else {
            MAIN.post(operation);
        }
    }

    private AudioRestoreController() {
    }

    static void inspectAssociation(Context context, int associationId) {
        final Context appContext = context.getApplicationContext();
        onMain(() -> inspectAssociationOnMain(
                appContext, associationId));
    }

    private static void inspectAssociationOnMain(
            Context context, int associationId) {
        if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "PERMISSION_REQUIRED");
            return;
        }

        CompanionDeviceManager manager =
                context.getSystemService(CompanionDeviceManager.class);

        if (manager == null) {
            Log.w(TAG, "CDM_UNAVAILABLE");
            return;
        }

        List<AssociationInfo> associations = manager.getMyAssociations();
        if (associations == null) {
            Log.w(TAG, "ASSOCIATIONS_UNAVAILABLE");
            return;
        }

        for (AssociationInfo association : associations) {
            if (association.getId() != associationId) {
                continue;
            }

            if (association.getDeviceMacAddress() == null) {
                Log.w(TAG, "ASSOCIATION_WITHOUT_MAC id=" + associationId);
                return;
            }

            String address = association.getDeviceMacAddress().toString();
            JSONObject profile = AudioProfileStore.load(context, address);

            if (profile == null) {
                Log.i(TAG, "PROFILE_NOT_FOUND id=" + associationId);
                return;
            }

            if (!profile.optBoolean("autoRestore", false)) {
                Log.i(TAG, "AUTO_RESTORE_DISABLED id=" + associationId);
                return;
            }

            if (RodinActivity.isAudioRestoreOwnerActive()) {
                Log.i(TAG, "ACTIVITY_OWNS_AUDIO_RESTORE id="
                        + associationId);
                return;
            }

            Log.i(TAG, "PROFILE_READY id=" + associationId
                    + " codec=" + profile.optInt("codec", -1)
                    + " sampleRate=" + profile.optInt("sampleRate", -1)
                    + " bits=" + profile.optInt("bits", -1));

            if (activeAssociationId == associationId) {
                Log.i(TAG, "A2DP_INSPECTION_ALREADY_ACTIVE");
                return;
            }

            if (activeCancellation != null) {
                activeCancellation.run();
            }

            activeAssociationId = associationId;
            inspectA2dp(context, address, associationId);
            return;
        }

        Log.w(TAG, "ASSOCIATION_NOT_FOUND id=" + associationId);
    }

    static void cancelAssociation(int associationId) {
        onMain(() -> {
            if (activeAssociationId != associationId) return;

            if (activeCancellation != null) {
                activeCancellation.run();
            }
        });
    }

    private static String applyCodecPreference(
            BluetoothProfile proxy,
            BluetoothDevice device,
            int codecType,
            int sampleRate,
            int bitsPerSample,
            int ldacQuality) {

        if (proxy == null) return "A2DP_UNAVAILABLE";
        if (device == null) return "DEVICE_UNAVAILABLE";

        if (RodinActivity.isAudioRestoreOwnerActive()) {
            return "ACTIVITY_OWNS_AUDIO_RESTORE";
        }

        try {
            if (proxy.getConnectionState(device)
                    != BluetoothProfile.STATE_CONNECTED) {
                return "A2DP_DEVICE_DISCONNECTED";
            }

            java.lang.reflect.Method activeMethod =
                    proxy.getClass().getDeclaredMethod("getActiveDevice");

            Object active = activeMethod.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return "ACTIVE_DEVICE_UNVERIFIED";
            }

            java.lang.reflect.Method statusMethod =
                    proxy.getClass().getDeclaredMethod(
                            "getCodecStatus", BluetoothDevice.class);

            Object result = statusMethod.invoke(proxy, device);

            if (!(result instanceof android.bluetooth.BluetoothCodecStatus)) {
                return "CODEC_STATUS_UNAVAILABLE";
            }

            android.bluetooth.BluetoothCodecStatus status =
                    (android.bluetooth.BluetoothCodecStatus) result;

            android.bluetooth.BluetoothCodecConfig currentConfig =
                    status.getCodecConfig();

            if (currentConfig == null) {
                return "CODEC_CONFIG_UNAVAILABLE";
            }

            java.util.List<android.bluetooth.BluetoothCodecConfig>
                    capabilities = status.getCodecsSelectableCapabilities();

            if (capabilities == null) {
                return "CAPABILITIES_UNAVAILABLE";
            }

            android.bluetooth.BluetoothCodecConfig selected = null;

            for (android.bluetooth.BluetoothCodecConfig capability
                    : capabilities) {
                if (capability.getCodecType() == codecType
                        && (capability.getSampleRate() & sampleRate) != 0
                        && (capability.getBitsPerSample() & bitsPerSample) != 0) {
                    selected = capability;
                    break;
                }
            }

            if (selected == null) return "UNSUPPORTED_SELECTION";

            int channelMode = selected.getChannelMode()
                    & currentConfig.getChannelMode();

            if (channelMode == 0) {
                channelMode = selected.getChannelMode()
                        & android.bluetooth.BluetoothCodecConfig
                            .CHANNEL_MODE_STEREO;
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

            android.bluetooth.BluetoothCodecConfig requested =
                    builder.build();

            if (!status.isCodecConfigSelectable(requested)) {
                return "CONFIG_NOT_SELECTABLE";
            }

            if (RodinActivity.isAudioRestoreOwnerActive()) {
                return "ACTIVITY_OWNS_AUDIO_RESTORE";
            }

            java.lang.reflect.Method applyMethod =
                    proxy.getClass().getDeclaredMethod(
                            "setCodecConfigPreference",
                            BluetoothDevice.class,
                            android.bluetooth.BluetoothCodecConfig.class);

            if (proxy.getConnectionState(device)
                    != BluetoothProfile.STATE_CONNECTED) {
                return "A2DP_DEVICE_DISCONNECTED";
            }

            applyMethod.invoke(proxy, device, requested);

            return "REQUEST_SENT";

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

    private static final int CODEC_STATE_UNKNOWN = -1;
    private static final int CODEC_STATE_MISMATCH = 0;
    private static final int CODEC_STATE_MATCH = 1;

    private static int readCodecConfigurationState(
            BluetoothProfile proxy,
            BluetoothDevice device,
            int codec,
            int sampleRate,
            int bits,
            int ldacQuality) {

        if (proxy == null || device == null) {
            return CODEC_STATE_UNKNOWN;
        }

        try {
            java.lang.reflect.Method activeMethod =
                    proxy.getClass().getDeclaredMethod("getActiveDevice");

            Object active = activeMethod.invoke(proxy);

            if (!(active instanceof BluetoothDevice)
                    || !device.equals(active)) {
                return CODEC_STATE_UNKNOWN;
            }

            java.lang.reflect.Method statusMethod =
                    proxy.getClass().getDeclaredMethod(
                            "getCodecStatus", BluetoothDevice.class);

            Object result = statusMethod.invoke(proxy, device);

            if (!(result instanceof android.bluetooth.BluetoothCodecStatus)) {
                return CODEC_STATE_UNKNOWN;
            }

            android.bluetooth.BluetoothCodecConfig config =
                    ((android.bluetooth.BluetoothCodecStatus) result)
                            .getCodecConfig();

            if (config == null) {
                return CODEC_STATE_UNKNOWN;
            }

            boolean matches =
                    config.getCodecType() == codec
                    && config.getSampleRate() == sampleRate
                    && config.getBitsPerSample() == bits
                    && (ldacQuality == -1
                        || (codec == 4
                            && config.getCodecSpecific1() == ldacQuality));

            return matches
                    ? CODEC_STATE_MATCH
                    : CODEC_STATE_MISMATCH;

        } catch (ReflectiveOperationException
                | SecurityException exception) {
            Log.w(TAG, "A2DP_CODEC_STATE_READ_FAILED", exception);
            return CODEC_STATE_UNKNOWN;
        } catch (RuntimeException exception) {
            Log.w(TAG, "A2DP_CODEC_STATE_RUNTIME_FAILED", exception);
            return CODEC_STATE_UNKNOWN;
        }
    }

    private static void inspectA2dp(
            Context context, String address, int associationId) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();

        if (adapter == null || !adapter.isEnabled()) {
            Log.w(TAG, "BLUETOOTH_UNAVAILABLE");

            if (activeAssociationId == associationId
                    && activeCancellation == null) {
                activeAssociationId = -1;
                Log.i(TAG, "A2DP_STATE_RESET");
            }

            return;
        }

        final Context appContext = context.getApplicationContext();
        final Handler handler = MAIN;
        final boolean[] finished = {false};
        final BluetoothProfile[] proxyHolder = {null};
        final BluetoothProfile.ServiceListener[] listenerHolder = {null};

        final Runnable[] cleanupHolder = {null};
        final Runnable[] timeoutHolder = {null};
        final Runnable[] retryHolder = {null};
        final int[] attempts = {0};

        // CDM restoration lifecycle state.
        // All pending callbacks are canceled during cleanup.
        final Runnable[] restoreHolder = {null};
        final Runnable[] restoreDeadlineHolder = {null};
        final int[] restoreRequestsSent = {0};
        final int[] restoreVerificationAttempts = {0};
        final int[] restoreRequestFailures = {0};
        final boolean[] restoreRequestPending = {false};

        final Runnable cleanup = () -> {
            if (finished[0]) return;
            finished[0] = true;

            if (timeoutHolder[0] != null) {
                handler.removeCallbacks(timeoutHolder[0]);
            }

            if (retryHolder[0] != null) {
                handler.removeCallbacks(retryHolder[0]);
            }

            if (restoreHolder[0] != null) {
                handler.removeCallbacks(restoreHolder[0]);
            }

            if (restoreDeadlineHolder[0] != null) {
                handler.removeCallbacks(restoreDeadlineHolder[0]);
            }

            if (activeCancellation == cleanupHolder[0]) {
                activeAssociationId = -1;
                activeCancellation = null;
            }

            if (proxyHolder[0] != null) {
                BluetoothProfile closing = proxyHolder[0];
                proxyHolder[0] = null;
                try {
                    adapter.closeProfileProxy(
                            BluetoothProfile.A2DP, closing);
                } catch (RuntimeException exception) {
                    Log.w(TAG, "A2DP_PROXY_CLOSE_FAILED", exception);
                }
            }
        };

        cleanupHolder[0] = cleanup;
        activeCancellation = cleanup;

        listenerHolder[0] = new BluetoothProfile.ServiceListener() {
            @Override
            public void onServiceConnected(
                    int profile, BluetoothProfile proxy) {
                onMain(() -> handleConnected(profile, proxy));
            }

            private void handleConnected(
                    int profile, BluetoothProfile proxy) {
                if (profile != BluetoothProfile.A2DP) return;

                if (finished[0]) {
                    try {
                        adapter.closeProfileProxy(profile, proxy);
                    } catch (RuntimeException exception) {
                        Log.w(TAG, "A2DP_LATE_PROXY_CLOSE_FAILED",
                                exception);
                    }
                    return;
                }

                proxyHolder[0] = proxy;

                if (RodinActivity.isAudioRestoreOwnerActive()) {
                    Log.i(TAG, "ACTIVITY_TOOK_AUDIO_RESTORE_OWNERSHIP");
                    cleanup.run();
                    return;
                }

                retryHolder[0] = new Runnable() {
                    @Override
                    public void run() {
                        if (finished[0]) return;

                        if (RodinActivity.isAudioRestoreOwnerActive()) {
                            Log.i(TAG, "ACTIVITY_TOOK_AUDIO_RESTORE_OWNERSHIP");
                            cleanup.run();
                            return;
                        }

                        attempts[0]++;

                        try {
                            java.lang.reflect.Method method =
                                    proxy.getClass().getDeclaredMethod(
                                            "getActiveDevice");

                            Object active = method.invoke(proxy);

                            if (!(active instanceof BluetoothDevice)) {
                                Log.i(TAG, "A2DP_WAITING attempt="
                                        + attempts[0]);

                                if (attempts[0] < 5) {
                                    handler.postDelayed(this, 600L);
                                } else {
                                    Log.w(TAG, "A2DP_RETRIES_EXHAUSTED");
                                    cleanup.run();
                                }

                                return;
                            }

                            String activeAddress =
                                    ((BluetoothDevice) active).getAddress();

                            if (!address.equalsIgnoreCase(activeAddress)) {
                                Log.w(TAG, "A2DP_ACTIVE_DEVICE_MISMATCH");
                                cleanup.run();
                                return;
                            }

                            Log.i(TAG, "A2DP_ACTIVE_DEVICE_MATCH");

                            if (RodinActivity.isAudioRestoreOwnerActive()) {
                                Log.i(TAG, "ACTIVITY_TOOK_AUDIO_RESTORE_OWNERSHIP");
                                cleanup.run();
                                return;
                            }

                            JSONObject saved =
                                    AudioProfileStore.load(appContext, address);

                            if (saved == null
                                    || !saved.optBoolean("autoRestore", false)) {
                                Log.i(TAG, "A2DP_PROFILE_DISABLED_OR_MISSING");
                                cleanup.run();
                                return;
                            }

                            int codec = saved.optInt("codec", -1);
                            int rate = saved.optInt("sampleRate", -1);
                            int bits = saved.optInt("bits", -1);
                            int quality = saved.optInt("version", 1) == 2
                                    ? saved.optInt("ldacQuality", -1)
                                    : -1;

                            if (codec < 0 || rate <= 0 || bits <= 0
                                    || (quality != -1
                                        && (codec != 4
                                            || quality < 1000
                                            || quality > 1003))) {
                                Log.w(TAG, "A2DP_PROFILE_INVALID");
                                cleanup.run();
                                return;
                            }

                            final BluetoothDevice restoreDevice =
                                    (BluetoothDevice) active;

                            int initialState = readCodecConfigurationState(
                                    proxy, restoreDevice,
                                    codec, rate, bits, quality);

                            if (initialState == CODEC_STATE_MATCH) {
                                Log.i(TAG, "A2DP_CODEC_ALREADY_ACTIVE");
                                cleanup.run();
                                return;
                            }

                            if (initialState == CODEC_STATE_UNKNOWN) {
                                Log.w(TAG, "A2DP_CODEC_STATE_UNKNOWN");
                                cleanup.run();
                                return;
                            }

                            Log.i(TAG, "A2DP_CODEC_RESTORE_NEEDED");

                            // Snapshot of the configuration that initiated
                            // this restoration operation.
                            final int expectedCodec = codec;
                            final int expectedRate = rate;
                            final int expectedBits = bits;
                            final int expectedQuality = quality;

                            // The initial timeout guards proxy acquisition.
                            // Restoration has its own deadlines.
                            if (timeoutHolder[0] != null) {
                                handler.removeCallbacks(timeoutHolder[0]);
                                timeoutHolder[0] = null;
                            }

                            restoreDeadlineHolder[0] = () -> {
                                if (!finished[0]) {
                                    Log.w(TAG, "A2DP_RESTORE_DEADLINE_EXCEEDED");
                                    cleanup.run();
                                }
                            };

                            handler.postDelayed(
                                    restoreDeadlineHolder[0], 20000L);

                            restoreHolder[0] = new Runnable() {
                                @Override
                                public void run() {
                                    if (finished[0]) return;

                                    if (RodinActivity.isAudioRestoreOwnerActive()) {
                                        Log.i(TAG, "ACTIVITY_TOOK_AUDIO_RESTORE_OWNERSHIP");
                                        cleanup.run();
                                        return;
                                    }

                                    JSONObject latest =
                                            AudioProfileStore.load(
                                                    appContext, address);

                                    if (latest == null
                                            || !latest.optBoolean(
                                                    "autoRestore", false)) {
                                        Log.i(TAG, "A2DP_RESTORE_PROFILE_DISABLED");
                                        cleanup.run();
                                        return;
                                    }

                                    int wantedCodec = latest.optInt("codec", -1);
                                    int wantedRate = latest.optInt("sampleRate", -1);
                                    int wantedBits = latest.optInt("bits", -1);
                                    int wantedQuality =
                                            latest.optInt("version", 1) == 2
                                                ? latest.optInt("ldacQuality", -1)
                                                : -1;

                                    if (wantedCodec < 0
                                            || wantedRate <= 0
                                            || wantedBits <= 0
                                            || (wantedQuality != -1
                                                && (wantedCodec != 4
                                                    || wantedQuality < 1000
                                                    || wantedQuality > 1003))) {
                                        Log.w(TAG, "A2DP_RESTORE_PROFILE_INVALID");
                                        cleanup.run();
                                        return;
                                    }

                                    if (wantedCodec != expectedCodec
                                            || wantedRate != expectedRate
                                            || wantedBits != expectedBits
                                            || wantedQuality != expectedQuality) {
                                        Log.i(TAG,
                                                "A2DP_RESTORE_PROFILE_CHANGED");
                                        cleanup.run();
                                        return;
                                    }

                                    int currentState =
                                            readCodecConfigurationState(
                                                    proxy, restoreDevice,
                                                    wantedCodec, wantedRate,
                                                    wantedBits, wantedQuality);

                                    if (currentState == CODEC_STATE_MATCH) {
                                        Log.i(TAG, "A2DP_RESTORE_VERIFIED");
                                        cleanup.run();
                                        return;
                                    }

                                    if (currentState == CODEC_STATE_UNKNOWN) {
                                        Log.w(TAG, "A2DP_RESTORE_STATE_UNKNOWN");
                                        cleanup.run();
                                        return;
                                    }

                                    if (!restoreRequestPending[0]) {
                                        String result = applyCodecPreference(
                                                proxy, restoreDevice,
                                                wantedCodec, wantedRate,
                                                wantedBits, wantedQuality);

                                        if (!"REQUEST_SENT".equals(result)) {
                                            Log.w(TAG, "A2DP_RESTORE_REQUEST_FAILED:"
                                                    + result);

                                            if ("ACTIVITY_OWNS_AUDIO_RESTORE"
                                                    .equals(result)) {
                                                cleanup.run();
                                                return;
                                            }

                                            boolean retryable =
                                                    "A2DP_UNAVAILABLE".equals(result)
                                                    || "DEVICE_UNAVAILABLE".equals(result)
                                                    || "CODEC_STATUS_UNAVAILABLE".equals(result)
                                                    || "CODEC_CONFIG_UNAVAILABLE".equals(result)
                                                    || "CAPABILITIES_UNAVAILABLE".equals(result);

                                            if (!retryable
                                                    || ++restoreRequestFailures[0] >= 5) {
                                                cleanup.run();
                                                return;
                                            }

                                            handler.postDelayed(this, 1200L);
                                            return;
                                        }

                                        restoreRequestsSent[0]++;
                                        restoreRequestFailures[0] = 0;
                                        restoreVerificationAttempts[0] = 0;
                                        restoreRequestPending[0] = true;

                                        Log.i(TAG, "A2DP_RESTORE_REQUEST_SENT");

                                        // Wait for Bluetooth negotiation
                                        // before counting verification attempts.
                                        handler.postDelayed(this, 1200L);
                                        return;
                                    }

                                    restoreVerificationAttempts[0]++;

                                    if (restoreVerificationAttempts[0] >= 3) {
                                        if (restoreRequestsSent[0] >= 2) {
                                            Log.w(TAG,
                                                    "A2DP_RESTORE_VERIFICATION_EXHAUSTED");
                                            cleanup.run();
                                            return;
                                        }

                                        restoreRequestPending[0] = false;
                                        restoreVerificationAttempts[0] = 0;
                                        Log.i(TAG, "A2DP_RESTORE_REAPPLY");
                                    }

                                    handler.postDelayed(this, 1200L);
                                }
                            };

                            handler.postDelayed(restoreHolder[0], 1200L);

                        } catch (ReflectiveOperationException
                                | SecurityException exception) {
                            Log.w(TAG, "A2DP_DIAGNOSTIC_FAILED", exception);
                            cleanup.run();
                        }
                    }
                };

                retryHolder[0].run();
            }

            @Override
            public void onServiceDisconnected(int profile) {
                onMain(() -> {
                    if (profile == BluetoothProfile.A2DP) {
                        Log.i(TAG, "A2DP_SERVICE_DISCONNECTED");
                        cleanup.run();
                    }
                });
            }
        };

        timeoutHolder[0] = () -> {
            if (!finished[0]) {
                Log.w(TAG, "A2DP_PROXY_TIMEOUT");
                cleanup.run();
            }
        };

        handler.postDelayed(timeoutHolder[0], 5000L);

        try {
            boolean requested = adapter.getProfileProxy(
                    appContext,
                    listenerHolder[0],
                    BluetoothProfile.A2DP);

            if (!requested) {
                Log.w(TAG, "A2DP_PROXY_REQUEST_REJECTED");
                cleanup.run();
            }
        } catch (RuntimeException exception) {
            Log.w(TAG, "A2DP_PROXY_REQUEST_FAILED", exception);
            cleanup.run();
        }
    }
}
