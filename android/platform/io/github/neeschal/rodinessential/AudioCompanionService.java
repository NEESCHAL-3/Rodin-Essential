package io.github.neeschal.rodinessential;

import android.companion.AssociationInfo;
import android.companion.CompanionDeviceService;
import android.companion.DevicePresenceEvent;
import android.os.Build;
import android.util.Log;

public final class AudioCompanionService
        extends CompanionDeviceService {

    private static final String TAG = "RodinAudioCDM";

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "SERVICE_CREATED");
    }

    @Override
    public void onDestroy() {
        Log.i(TAG, "SERVICE_DESTROYED");
        super.onDestroy();
    }

    @Override
    public void onDeviceAppeared(AssociationInfo association) {
        if (association == null) {
            Log.w(TAG, "DEVICE_APPEARED_NULL");
            return;
        }

        Log.i(TAG, "DEVICE_APPEARED associationId="
                + association.getId());
    }

    @Override
    public void onDeviceDisappeared(AssociationInfo association) {
        if (association == null) {
            Log.w(TAG, "DEVICE_DISAPPEARED_NULL");
            return;
        }

        Log.i(TAG, "DEVICE_DISAPPEARED associationId="
                + association.getId());
    }

    @Override
    public void onDevicePresenceEvent(DevicePresenceEvent event) {
        if (event == null) {
            Log.w(TAG, "PRESENCE_EVENT_NULL");
            return;
        }

        final int associationId = event.getAssociationId();
        final int type = event.getEvent();

        switch (type) {
            case DevicePresenceEvent.EVENT_BT_CONNECTED:
                Log.i(TAG, "BT_CONNECTED associationId="
                        + associationId);
                AudioRestoreController.inspectAssociation(
                        this, associationId);
                break;

            case DevicePresenceEvent.EVENT_BT_DISCONNECTED:
                Log.i(TAG, "BT_DISCONNECTED associationId="
                        + associationId);
                AudioRestoreController.cancelAssociation(associationId);
                break;

            case DevicePresenceEvent.EVENT_BLE_APPEARED:
                Log.i(TAG, "BLE_APPEARED associationId="
                        + associationId);
                break;

            case DevicePresenceEvent.EVENT_BLE_DISAPPEARED:
                Log.i(TAG, "BLE_DISAPPEARED associationId="
                        + associationId);
                break;

            default:
                Log.i(TAG, "PRESENCE_EVENT type="
                        + type + " associationId="
                        + associationId);
                break;
        }
    }
}
