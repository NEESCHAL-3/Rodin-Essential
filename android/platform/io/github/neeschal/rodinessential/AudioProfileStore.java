package io.github.neeschal.rodinessential;

import android.content.Context;

final class AudioProfileStore {
    private static final String PREFS = "audio_device_profiles_v1";

    private static String key(String address) {
        String normalized = address == null
                ? null
                : address.toUpperCase(java.util.Locale.ROOT);

        if (normalized == null ||
                !android.bluetooth.BluetoothAdapter
                    .checkBluetoothAddress(normalized)) {
            throw new IllegalArgumentException(
                "Invalid Bluetooth device address");
        }

        return "device_" + normalized;
    }

    static void save(
            Context context,
            String address,
            String name,
            int codec,
            int sampleRate,
            int bits,
            boolean autoRestore) {
        save(context, address, name, codec, sampleRate, bits,
            -1, autoRestore);
    }

    static void save(
            Context context,
            String address,
            String name,
            int codec,
            int sampleRate,
            int bits,
            int ldacQuality,
            boolean autoRestore) {
        if (ldacQuality != -1 &&
                (codec != 4 ||
                 ldacQuality < 1000 ||
                 ldacQuality > 1003)) {
            throw new IllegalArgumentException(
                "Invalid LDAC quality for audio profile");
        }

        org.json.JSONObject profile = new org.json.JSONObject();

        try {
            profile.put("version", ldacQuality == -1 ? 1 : 2);
            profile.put("name", name != null ? name : "");
            profile.put("codec", codec);
            profile.put("sampleRate", sampleRate);
            profile.put("bits", bits);
            if (codec == 4 && ldacQuality != -1) {
                profile.put("ldacQuality", ldacQuality);
            }
            profile.put("autoRestore", autoRestore);
        } catch (org.json.JSONException exception) {
            throw new IllegalStateException(
                "Unable to serialize audio profile", exception);
        }

        boolean saved = context.getSharedPreferences(
                PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key(address), profile.toString())
            .commit();

        if (!saved) {
            throw new IllegalStateException(
                "Unable to persist audio profile");
        }
    }

    static org.json.JSONObject load(Context context, String address) {
        String value = context.getSharedPreferences(
                PREFS, Context.MODE_PRIVATE)
            .getString(key(address), null);

        if (value == null) return null;

        try {
            org.json.JSONObject profile =
                new org.json.JSONObject(value);

            int version = profile.optInt("version", -1);

            if (version != 1 && version != 2) {
                return null;
            }

            if (version == 2) {
                int codec = profile.optInt("codec", -1);
                int quality = profile.optInt("ldacQuality", -1);

                if (quality != -1 &&
                        (codec != 4 ||
                         quality < 1000 ||
                         quality > 1003)) {
                    return null;
                }
            }

            return profile;
        } catch (org.json.JSONException exception) {
            return null;
        }
    }


    static boolean setAutoRestore(
            Context context, String address, boolean enabled) {
        org.json.JSONObject profile = load(context, address);

        if (profile == null) return false;

        try {
            profile.put("autoRestore", enabled);
        } catch (org.json.JSONException exception) {
            return false;
        }

        return context.getSharedPreferences(
                PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(key(address), profile.toString())
            .commit();
    }

    static boolean delete(Context context, String address) {
        return context.getSharedPreferences(
                PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(key(address))
            .commit();
    }
}
