package io.github.neeschal.rodinessential;

import android.companion.AssociationInfo;
import android.companion.CompanionDeviceManager;
import android.companion.ObservingDevicePresenceRequest;
import android.content.Context;
import android.os.Build;
import android.util.Log;

public final class AudioPresenceObserver {

    private static final String TAG = "RodinAudioCDM";

    private AudioPresenceObserver() {}

    public static String setObserving(
            Context context,
            String address,
            boolean enabled) {

        if (context == null || address == null) {
            return "INVALID_ARGUMENT";
        }

        CompanionDeviceManager manager =
            (CompanionDeviceManager) context.getSystemService(
                Context.COMPANION_DEVICE_SERVICE);

        if (manager == null) {
            return "CDM_UNAVAILABLE";
        }

        try {
            AssociationInfo match = null;

            for (AssociationInfo association :
                    manager.getMyAssociations()) {

                android.net.MacAddress mac =
                    association.getDeviceMacAddress();

                if (mac != null &&
                        address.equalsIgnoreCase(mac.toString())) {
                    match = association;
                    break;
                }
            }

            if (match == null) {
                return "NOT_ASSOCIATED";
            }

            if (Build.VERSION.SDK_INT >= 36) {
                ObservingDevicePresenceRequest request =
                    new ObservingDevicePresenceRequest.Builder()
                        .setAssociationId(match.getId())
                        .build();

                if (enabled) {
                    manager.startObservingDevicePresence(request);
                } else {
                    manager.stopObservingDevicePresence(request);
                }
            } else {
                if (enabled) {
                    manager.startObservingDevicePresence(address);
                } else {
                    manager.stopObservingDevicePresence(address);
                }
            }

            String result = enabled
                ? "OBSERVATION_REGISTERED"
                : "OBSERVATION_STOPPED";

            Log.i(TAG, result + " associationId="
                    + match.getId());

            return result;

        } catch (SecurityException exception) {
            Log.e(TAG, "CDM permission denied", exception);
            return "PERMISSION_REQUIRED";

        } catch (RuntimeException exception) {
            Log.e(TAG, "CDM observation failed", exception);
            return "OBSERVATION_FAILED";
        }
    }
}
