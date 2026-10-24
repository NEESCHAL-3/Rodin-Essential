import 'dart:convert';
import 'dart:ffi' as ffi;

typedef _AudioAllocateNative = ffi.Pointer<ffi.Void> Function(ffi.IntPtr);
typedef _AudioAllocateDart = ffi.Pointer<ffi.Void> Function(int);

typedef _AudioReleaseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _AudioReleaseDart = void Function(ffi.Pointer<ffi.Void>);

typedef _AudioStatusNative = ffi.Int32 Function();
typedef _AudioStatusDart = int Function();

typedef _AudioDeviceNameNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.UintPtr);

typedef _AudioDeviceNameDart = int Function(ffi.Pointer<ffi.Uint8>, int);

typedef _AudioApplyNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _AudioApplyDart = int Function(int, int, int);

typedef _AudioApplyQualityNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _AudioApplyQualityDart = int Function(int, int, int, int);

typedef _AudioSaveNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _AudioSaveDart = int Function(int, int, int, int);

typedef _AudioSaveQualityNative =
    ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32, ffi.Int32);
typedef _AudioSaveQualityDart = int Function(int, int, int, int, int);
typedef _AudioDeleteNative = ffi.Int32 Function(ffi.Int32);
typedef _AudioDeleteDart = int Function(int);

typedef _AudioAutoRestoreNative = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _AudioAutoRestoreDart = int Function(int, int);

enum AudioBluetoothStatus { unavailable, disabled, permissionRequired, enabled }

final class AudioBackend {
  AudioBackend._();

  static final AudioBackend instance = AudioBackend._();

  _AudioStatusDart? _refreshDevice;
  _AudioStatusDart? _readConnectionGeneration;
  _AudioDeviceNameDart? _readDeviceName;
  _AudioStatusDart? _requestCodecDiagnostic;
  _AudioStatusDart? _requestSavedProfile;
  _AudioDeviceNameDart? _readSavedProfileResult;

  _AudioStatusDart? _requestCompanionStatus;
  _AudioDeviceNameDart? _readCompanionStatusResult;
  _AudioStatusDart? _requestCompanionAssociation;
  _AudioDeviceNameDart? _readCompanionAssociationResult;

  _AudioDeviceNameDart? _readCodecDiagnostic;

  _AudioApplyDart? _requestApplyCodec;
  _AudioApplyQualityDart? _requestApplyCodecWithQuality;
  _AudioStatusDart? _cancelPendingApply;
  _AudioDeviceNameDart? _readApplyCodecResult;
  _AudioSaveDart? _requestSaveProfile;
  _AudioSaveQualityDart? _requestSaveProfileWithQuality;
  _AudioDeleteDart? _requestDeleteProfile;

  _AudioAutoRestoreDart? _requestSetAutoRestore;
  _AudioDeviceNameDart? _readAutoRestoreResult;
  _AudioDeviceNameDart? _readSaveProfileResult;
  _AudioDeviceNameDart? _readDeleteProfileResult;

  _AudioStatusDart? _readStatus;
  _AudioStatusDart? _requestPermission;
  _AudioStatusDart? _readPermissionGeneration;

  /// Starts the official Android companion-device authorization flow.
  /// Authorization still requires explicit confirmation by the user.
  bool requestCompanionAssociation() {
    try {
      _requestCompanionAssociation ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_request_companion_association',
          );

      return _requestCompanionAssociation!() == 1;
    } catch (_) {
      return false;
    }
  }

  bool requestCompanionStatus() {
    try {
      _requestCompanionStatus ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_request_companion_status',
          );

      return _requestCompanionStatus!() == 1;
    } catch (_) {
      return false;
    }
  }

  String get companionStatusResult {
    const int capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readCompanionStatusResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_companion_status_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readCompanionStatusResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  String get companionAssociationResult {
    const int capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readCompanionAssociationResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_companion_association_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readCompanionAssociationResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  /// Changes only when Android reports an A2DP connection lifecycle event.
  /// Returns -1 when the native bridge is unavailable.
  int get connectionGeneration {
    try {
      _readConnectionGeneration ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_connection_generation',
          );

      return _readConnectionGeneration!();
    } catch (_) {
      return -1;
    }
  }

  /// Requests the saved profile for the verified active A2DP device.
  bool requestSavedProfile() {
    try {
      _requestSavedProfile ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_request_saved_profile',
          );

      return _requestSavedProfile!() == 1;
    } catch (_) {
      return false;
    }
  }

  /// Returns the latest asynchronous saved-profile query result.
  String get savedProfileResult {
    const int capacity = 4096;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readSavedProfileResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_saved_profile_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readSavedProfileResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  bool requestCodecDiagnostic() {
    try {
      _requestCodecDiagnostic ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_request_codec_diagnostic',
          );

      return _requestCodecDiagnostic!() == 1;
    } catch (_) {
      return false;
    }
  }

  /// Requests deletion of the verified active device's saved profile.
  bool requestDeleteProfile(int connectionGeneration) {
    if (connectionGeneration < 0) {
      return false;
    }

    try {
      _requestDeleteProfile ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeleteNative, _AudioDeleteDart>(
            'rodin_host_audio_request_delete_profile',
          );

      return _requestDeleteProfile!(connectionGeneration) == 1;
    } catch (_) {
      return false;
    }
  }

  bool requestSaveProfile(
    int codec,
    int sampleRate,
    int bitDepth,
    int connectionGeneration,
  ) {
    try {
      _requestSaveProfile ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioSaveNative, _AudioSaveDart>(
            'rodin_host_audio_request_save_profile',
          );

      return _requestSaveProfile!(
            codec,
            sampleRate,
            bitDepth,
            connectionGeneration,
          ) ==
          1;
    } catch (_) {
      return false;
    }
  }

  bool requestSaveProfileWithQuality(
    int codec,
    int sampleRate,
    int bitDepth,
    int ldacQuality,
    int connectionGeneration,
  ) {
    try {
      _requestSaveProfileWithQuality ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioSaveQualityNative, _AudioSaveQualityDart>(
            'rodin_host_audio_request_save_profile_with_quality',
          );

      return _requestSaveProfileWithQuality!(
            codec,
            sampleRate,
            bitDepth,
            ldacQuality,
            connectionGeneration,
          ) ==
          1;
    } catch (_) {
      return false;
    }
  }

  String get saveProfileResult {
    const int capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readSaveProfileResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_save_profile_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readSaveProfileResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  /// Requests persistence of the Auto Restore preference for the
  /// verified active Bluetooth device.
  bool requestSetAutoRestore(int connectionGeneration, bool enabled) {
    if (connectionGeneration < 0) return false;

    try {
      _requestSetAutoRestore ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioAutoRestoreNative, _AudioAutoRestoreDart>(
            'rodin_host_audio_request_set_auto_restore',
          );

      return _requestSetAutoRestore!(connectionGeneration, enabled ? 1 : 0) ==
          1;
    } catch (_) {
      return false;
    }
  }

  String get autoRestoreResult {
    const capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final libc = ffi.DynamicLibrary.open('libc.so');
      final allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readAutoRestoreResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_auto_restore_result',
          );

      buffer = allocate(capacity);
      if (buffer == ffi.nullptr) return 'BACKEND_UNAVAILABLE';

      final length = _readAutoRestoreResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) return 'BACKEND_ERROR';
      if (length == 0) return 'EMPTY_RESULT';

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  String get deleteProfileResult {
    const int capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readDeleteProfileResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_delete_profile_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readDeleteProfileResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  bool requestApplyCodec(int codec, int sampleRate, int bitDepth) {
    try {
      _requestApplyCodec ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioApplyNative, _AudioApplyDart>(
            'rodin_host_audio_request_apply_codec',
          );

      return _requestApplyCodec!(codec, sampleRate, bitDepth) == 1;
    } catch (_) {
      return false;
    }
  }

  bool requestApplyCodecWithQuality(
    int codec,
    int sampleRate,
    int bitDepth,
    int ldacQuality,
  ) {
    try {
      _requestApplyCodecWithQuality ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioApplyQualityNative, _AudioApplyQualityDart>(
            'rodin_host_audio_request_apply_codec_with_quality',
          );

      return _requestApplyCodecWithQuality!(
            codec,
            sampleRate,
            bitDepth,
            ldacQuality,
          ) ==
          1;
    } catch (_) {
      return false;
    }
  }

  bool cancelPendingApply() {
    try {
      _cancelPendingApply ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_cancel_pending_apply',
          );

      return _cancelPendingApply!() == 1;
    } catch (_) {
      return false;
    }
  }

  String get applyCodecResult {
    const int capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readApplyCodecResult ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_apply_codec_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readApplyCodecResult!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  String get codecDiagnosticResult {
    const int capacity = 4096;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readCodecDiagnostic ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_codec_diagnostic_result',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return 'BACKEND_UNAVAILABLE';
      }

      final int length = _readCodecDiagnostic!(
        buffer.cast<ffi.Uint8>(),
        capacity,
      );

      if (length < 0 || length >= capacity) {
        return 'BACKEND_ERROR';
      }

      if (length == 0) {
        return 'EMPTY_RESULT';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return 'BACKEND_UNAVAILABLE';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  bool refreshConnectedDevice() {
    try {
      _refreshDevice ??= ffi.DynamicLibrary.open('librodin_essential_host.so')
          .lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_refresh_device',
          );

      return _refreshDevice!() == 1;
    } catch (_) {
      return false;
    }
  }

  String get connectedDeviceName {
    const int capacity = 512;

    ffi.Pointer<ffi.Void> buffer = ffi.nullptr;
    _AudioReleaseDart? release;

    try {
      final ffi.DynamicLibrary libc = ffi.DynamicLibrary.open('libc.so');

      final _AudioAllocateDart allocate = libc
          .lookupFunction<_AudioAllocateNative, _AudioAllocateDart>('malloc');

      release = libc.lookupFunction<_AudioReleaseNative, _AudioReleaseDart>(
        'free',
      );

      _readDeviceName ??= ffi.DynamicLibrary.open('librodin_essential_host.so')
          .lookupFunction<_AudioDeviceNameNative, _AudioDeviceNameDart>(
            'rodin_host_audio_device_name',
          );

      buffer = allocate(capacity);

      if (buffer == ffi.nullptr) {
        return '';
      }

      final int length = _readDeviceName!(buffer.cast<ffi.Uint8>(), capacity);

      if (length <= 0 || length >= capacity) {
        return '';
      }

      return utf8.decode(
        buffer.cast<ffi.Uint8>().asTypedList(length),
        allowMalformed: true,
      );
    } catch (_) {
      return '';
    } finally {
      if (buffer != ffi.nullptr && release != null) {
        release(buffer);
      }
    }
  }

  int get permissionGeneration {
    try {
      _readPermissionGeneration ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_permission_generation',
          );

      return _readPermissionGeneration!();
    } catch (_) {
      return -1;
    }
  }

  bool requestBluetoothPermission() {
    try {
      _requestPermission ??=
          ffi.DynamicLibrary.open(
            'librodin_essential_host.so',
          ).lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_request_permission',
          );

      return _requestPermission!() == 1;
    } catch (_) {
      return false;
    }
  }

  AudioBluetoothStatus get bluetoothStatus {
    try {
      _readStatus ??= ffi.DynamicLibrary.open('librodin_essential_host.so')
          .lookupFunction<_AudioStatusNative, _AudioStatusDart>(
            'rodin_host_audio_bluetooth_status',
          );

      final int value = _readStatus!();

      return switch (value) {
        1 => AudioBluetoothStatus.disabled,
        2 => AudioBluetoothStatus.permissionRequired,
        3 => AudioBluetoothStatus.enabled,
        _ => AudioBluetoothStatus.unavailable,
      };
    } catch (_) {
      return AudioBluetoothStatus.unavailable;
    }
  }
}
