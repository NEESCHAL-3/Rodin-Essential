import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;

typedef _BackendGetNative = ffi.Int32 Function(ffi.Int32);
typedef _BackendGetDart = int Function(int);
typedef _BackendSetNative = ffi.Int32 Function(ffi.Int32, ffi.Int32, ffi.Int32);
typedef _BackendSetDart = int Function(int, int, int);

final class RodinInstalledApp {
  const RodinInstalledApp({
    required this.index,
    required this.packageName,
    required this.label,
    required this.system,
    this.iconPath = '',
  });

  final int index;
  final String packageName;
  final String label;
  final bool system;
  final String iconPath;
}

final class RodinBackendSnapshot {
  const RodinBackendSnapshot({
    required this.ready,
    required this.actionState,
    required this.chargingWriteState,
    required this.chargingMode,
    required this.batteryCapacity,
    required this.batteryTempTenthsC,
    required this.batteryVoltageUv,
    required this.batteryCurrentUa,
    required this.batteryStatus,
    required this.batteryHealth,
    required this.usbOnline,
    required this.usbType,
    required this.cpuOnlineMask,
    required this.cpuFreqKhz,
    required this.cpuGovernor0,
    required this.cpuGovernor4,
    required this.cpuGovernor7,
    required this.gpuGovernor,
    required this.ufsScheduler,
    required this.touchHal,
    required this.displayHal,
    required this.touchState,
    required this.displayColor,
    required this.displayTemp,
    required this.sunlight,
    required this.silky,
    required this.video,
    required this.dolby,
    required this.performanceProfile,
  });

  final bool ready;
  final int actionState;
  final int chargingWriteState;
  final int chargingMode;
  final int batteryCapacity;
  final int batteryTempTenthsC;
  final int batteryVoltageUv;
  final int batteryCurrentUa;
  final int batteryStatus;
  final int batteryHealth;
  final int usbOnline;
  final int usbType;
  final int cpuOnlineMask;
  final List<int> cpuFreqKhz;
  final int cpuGovernor0;
  final int cpuGovernor4;
  final int cpuGovernor7;
  final int gpuGovernor;
  final int ufsScheduler;
  final int touchHal;
  final int displayHal;
  final int touchState;
  final int displayColor;
  final int displayTemp;
  final int sunlight;
  final int silky;
  final int video;
  final int dolby;
  final int performanceProfile;

  bool get chargingBoost => chargingMode == 8;
  bool get busy => actionState == 1;
  double? get batteryTempC =>
      batteryTempTenthsC >= 0 ? batteryTempTenthsC / 10.0 : null;
  double? get batteryVoltageV =>
      batteryVoltageUv >= 0 ? batteryVoltageUv / 1000000.0 : null;
  double? get batteryCurrentA => batteryCurrentUa != -9223372036854775808
      ? batteryCurrentUa / 1000000.0
      : null;

  bool cpuOnline(int cpu) =>
      cpu >= 0 && cpu < 32 && (cpuOnlineMask & (1 << cpu)) != 0;
}

typedef _I32Native = ffi.Int32 Function();
typedef _I32Dart = int Function();
typedef _I64Native = ffi.Int64 Function();
typedef _I64Dart = int Function();
typedef _U32Native = ffi.Uint32 Function();
typedef _U32Dart = int Function();
typedef _U32ToI64Native = ffi.Int64 Function(ffi.Uint32);
typedef _U32ToI64Dart = int Function(int);
typedef _SetI32Native = ffi.Int32 Function(ffi.Int32);
typedef _SetI32Dart = int Function(int);
typedef _I32ToI32Native = ffi.Int32 Function(ffi.Int32);
typedef _I32ToI32Dart = int Function(int);
typedef _SetTwoI32Native = ffi.Int32 Function(ffi.Int32, ffi.Int32);
typedef _SetTwoI32Dart = int Function(int, int);

final class RodinBackend {
  RodinBackend._();
  static final RodinBackend instance = RodinBackend._();

  ffi.DynamicLibrary? _lib;
  Timer? _timer;
  bool _started = false;

  final StreamController<RodinBackendSnapshot> _controller =
      StreamController<RodinBackendSnapshot>.broadcast(sync: true);
  final Map<int, List<int>> _cpuFrequencyTables = <int, List<int>>{};

  late _I32Dart _startNative;
  late _I32Dart _refreshNative;
  late _I32Dart _readyNative;
  late _I32Dart _actionStateNative;
  late _I32Dart _chargingWriteStateNative;
  late _I32Dart _chargingModeNative;
  late _SetI32Dart _setChargingModeNative;
  late _I32Dart _batteryCapacityNative;
  late _I32Dart _batteryTempNative;
  late _I64Dart _batteryVoltageNative;
  late _I64Dart _batteryCurrentNative;
  late _I32Dart _batteryStatusNative;
  late _I32Dart _batteryHealthNative;
  late _I32Dart _usbOnlineNative;
  late _I32Dart _usbTypeNative;
  late _U32Dart _cpuOnlineMaskNative;
  late _U32ToI64Dart _cpuFreqNative;
  late _I32ToI32Dart _cpuGovernorNative;
  late _SetTwoI32Dart _setCpuGovernorNative;
  late _I32ToI32Dart _cpuAvailableCountNative;
  late _SetTwoI32Dart _cpuAvailableFreqNative;
  late _I32Dart _gpuGovernorNative;
  late _SetI32Dart _setGpuGovernorNative;
  late _I32Dart _ufsSchedulerNative;
  late _SetI32Dart _setUfsSchedulerNative;
  late _I32Dart _touchHalNative;
  late _I32Dart _displayHalNative;
  late _I32Dart _touchStateNative;
  late _SetI32Dart _setTouchStateNative;
  late _I32Dart _displayColorNative;
  late _SetI32Dart _setDisplayColorNative;
  late _I32Dart _displayTempNative;
  late _SetI32Dart _setDisplayTempNative;
  late _I32Dart _sunlightNative;
  late _SetI32Dart _setSunlightNative;
  late _I32Dart _silkyNative;
  late _SetI32Dart _setSilkyNative;
  late _I32Dart _videoNative;
  late _SetI32Dart _setVideoNative;
  late _I32Dart _dolbyNative;
  late _SetI32Dart _setDolbyNative;
  late _I32Dart _performanceNative;
  late _SetI32Dart _setPerformanceNative;
  late _SetI32Dart _openSupportLinkNative;
  late _I32Dart _photoPermissionStateNative;
  late _I32Dart _requestPhotoPermissionNative;
  late _SetI32Dart _hapticNative;
  late _BackendGetDart _backendGetNative;
  late _BackendSetDart _backendSetNative;
  late _I32Dart _appsRefreshNative;
  late _I32Dart _appsRevisionNative;
  late _I32Dart _appsCountNative;
  late _I32Dart _appsBlobLenNative;
  late _I32ToI32Dart _appsBlobByteNative;
  late _I32ToI32Dart _appProfileNative;
  late _SetTwoI32Dart _setAppProfileNative;
  late _I32Dart _activeAppIndexNative;
  late _SetI32Dart _setBackInterceptNative;
  late _I32Dart _consumeBackRequestNative;

  RodinBackendSnapshot _latest = const RodinBackendSnapshot(
    ready: false,
    actionState: 0,
    chargingWriteState: 0,
    chargingMode: -1,
    batteryCapacity: -1,
    batteryTempTenthsC: -1,
    batteryVoltageUv: -1,
    batteryCurrentUa: -9223372036854775808,
    batteryStatus: -1,
    batteryHealth: -1,
    usbOnline: -1,
    usbType: -1,
    cpuOnlineMask: 0,
    cpuFreqKhz: <int>[-1, -1, -1, -1, -1, -1, -1, -1],
    cpuGovernor0: -1,
    cpuGovernor4: -1,
    cpuGovernor7: -1,
    gpuGovernor: -1,
    ufsScheduler: -1,
    touchHal: 0,
    displayHal: 0,
    touchState: -1,
    displayColor: -1,
    displayTemp: -1,
    sunlight: -1,
    silky: -1,
    video: -1,
    dolby: -1,
    performanceProfile: -1,
  );

  RodinBackendSnapshot get latest => _latest;
  Stream<RodinBackendSnapshot> get snapshots => _controller.stream;
  bool get started => _started;

  bool start() {
    if (_started) return true;
    try {
      final ffi.DynamicLibrary lib = ffi.DynamicLibrary.open(
        'librodin_essential_host.so',
      );
      _startNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_start',
      );
      _refreshNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_refresh',
      );
      _readyNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_ready',
      );
      _actionStateNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_action_state',
      );
      _chargingWriteStateNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_charging_write_state',
      );
      _chargingModeNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_charging_mode',
      );
      _setChargingModeNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_charging_mode',
      );
      _batteryCapacityNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_battery_capacity',
      );
      _batteryTempNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_battery_temp_tenths_c',
      );
      _batteryVoltageNative = lib.lookupFunction<_I64Native, _I64Dart>(
        'rodin_backend_get_battery_voltage_uv',
      );
      _batteryCurrentNative = lib.lookupFunction<_I64Native, _I64Dart>(
        'rodin_backend_get_battery_current_ua',
      );
      _batteryStatusNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_battery_status',
      );
      _batteryHealthNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_battery_health',
      );
      _usbOnlineNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_usb_online',
      );
      _usbTypeNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_usb_type',
      );
      _cpuOnlineMaskNative = lib.lookupFunction<_U32Native, _U32Dart>(
        'rodin_backend_get_cpu_online_mask',
      );
      _cpuFreqNative = lib.lookupFunction<_U32ToI64Native, _U32ToI64Dart>(
        'rodin_backend_get_cpu_freq_khz',
      );
      _cpuGovernorNative = lib.lookupFunction<_I32ToI32Native, _I32ToI32Dart>(
        'rodin_backend_get_cpu_governor',
      );
      _setCpuGovernorNative = lib
          .lookupFunction<_SetTwoI32Native, _SetTwoI32Dart>(
            'rodin_backend_set_cpu_governor',
          );
      _cpuAvailableCountNative = lib
          .lookupFunction<_I32ToI32Native, _I32ToI32Dart>(
            'rodin_backend_get_cpu_available_count',
          );
      _cpuAvailableFreqNative = lib
          .lookupFunction<_SetTwoI32Native, _SetTwoI32Dart>(
            'rodin_backend_get_cpu_available_freq',
          );
      _gpuGovernorNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_gpu_governor',
      );
      _setGpuGovernorNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_gpu_governor',
      );
      _ufsSchedulerNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_ufs_scheduler',
      );
      _setUfsSchedulerNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_ufs_scheduler',
      );
      _touchHalNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_touch_hal',
      );
      _displayHalNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_display_hal',
      );
      _touchStateNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_touch_state',
      );
      _setTouchStateNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_touch_state',
      );
      _displayColorNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_display_color',
      );
      _setDisplayColorNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_display_color',
      );
      _displayTempNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_display_temp',
      );
      _setDisplayTempNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_display_temp',
      );
      _sunlightNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_sunlight',
      );
      _setSunlightNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_sunlight',
      );
      _silkyNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_silky',
      );
      _setSilkyNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_silky',
      );
      _videoNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_video',
      );
      _setVideoNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_video',
      );
      _dolbyNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_dolby',
      );
      _setDolbyNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_dolby',
      );
      _performanceNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_backend_get_performance_profile',
      );
      _setPerformanceNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_set_performance_profile',
      );
      _openSupportLinkNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_backend_open_support_link',
      );
      _hapticNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_host_haptic',
      );
      _backendGetNative = lib
          .lookupFunction<_BackendGetNative, _BackendGetDart>(
            'rodin_backend_extended_get',
          );
      _backendSetNative = lib
          .lookupFunction<_BackendSetNative, _BackendSetDart>(
            'rodin_backend_extended_set',
          );

      _appsRefreshNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_apps_refresh',
      );
      _appsRevisionNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_apps_revision',
      );
      _appsCountNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_apps_count',
      );
      _appsBlobLenNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_apps_blob_len',
      );
      _appsBlobByteNative = lib.lookupFunction<_I32ToI32Native, _I32ToI32Dart>(
        'rodin_host_apps_blob_byte',
      );
      _appProfileNative = lib.lookupFunction<_I32ToI32Native, _I32ToI32Dart>(
        'rodin_host_app_profile',
      );
      _setAppProfileNative = lib
          .lookupFunction<_SetTwoI32Native, _SetTwoI32Dart>(
            'rodin_host_set_app_profile',
          );
      _activeAppIndexNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_active_app_index',
      );

      _setBackInterceptNative = lib.lookupFunction<_SetI32Native, _SetI32Dart>(
        'rodin_host_set_back_intercept',
      );
      _consumeBackRequestNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_consume_back_request',
      );

      _photoPermissionStateNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_photo_permission_state',
      );
      _requestPhotoPermissionNative = lib.lookupFunction<_I32Native, _I32Dart>(
        'rodin_host_request_photo_permission',
      );

      _lib = lib;
      _started = _startNative() == 1;
      if (_started) {
        _refreshNative();
        _poll();
        _timer = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => _poll(),
        );
      }
      return _started;
    } catch (_) {
      _started = false;
      return false;
    }
  }

  void _poll() {
    if (!_started || _lib == null) return;
    final RodinBackendSnapshot next = RodinBackendSnapshot(
      ready: _readyNative() == 1,
      actionState: _actionStateNative(),
      chargingWriteState: _chargingWriteStateNative(),
      chargingMode: _chargingModeNative(),
      batteryCapacity: _batteryCapacityNative(),
      batteryTempTenthsC: _batteryTempNative(),
      batteryVoltageUv: _batteryVoltageNative(),
      batteryCurrentUa: _batteryCurrentNative(),
      batteryStatus: _batteryStatusNative(),
      batteryHealth: _batteryHealthNative(),
      usbOnline: _usbOnlineNative(),
      usbType: _usbTypeNative(),
      cpuOnlineMask: _cpuOnlineMaskNative(),
      cpuFreqKhz: List<int>.generate(8, _cpuFreqNative, growable: false),
      cpuGovernor0: _cpuGovernorNative(0),
      cpuGovernor4: _cpuGovernorNative(4),
      cpuGovernor7: _cpuGovernorNative(7),
      gpuGovernor: _gpuGovernorNative(),
      ufsScheduler: _ufsSchedulerNative(),
      touchHal: _touchHalNative(),
      displayHal: _displayHalNative(),
      touchState: _touchStateNative(),
      displayColor: _displayColorNative(),
      displayTemp: _displayTempNative(),
      sunlight: _sunlightNative(),
      silky: _silkyNative(),
      video: _videoNative(),
      dolby: _dolbyNative(),
      performanceProfile: _performanceNative(),
    );
    _latest = next;
    _controller.add(next);
  }

  bool _queue(int rc) {
    final bool accepted = _started && rc == 1;
    if (!accepted) return false;

    Timer(const Duration(milliseconds: 24), _poll);
    Timer(const Duration(milliseconds: 64), _poll);
    Timer(const Duration(milliseconds: 120), _poll);
    Timer(const Duration(milliseconds: 220), _poll);

    return true;
  }

  bool setChargingBoost(bool enabled) =>
      _queue(_setChargingModeNative(enabled ? 8 : 0));
  bool setTouchProfile(int profile) {
    if (profile < 0 || profile > 7) return false;
    return _queue(_setTouchStateNative(profile));
  }

  // Kept for older call sites outside the Flutter screen bundle. Enabled maps
  // to Rodin's sustained 480 Hz profile; disabled restores OEM Dynamic.
  bool setTouchBoost(bool enabled) => setTouchProfile(enabled ? 2 : 0);
  bool setDisplayColor(int mode) => _queue(_setDisplayColorNative(mode));
  bool setDisplayTemperature(int mode) => _queue(_setDisplayTempNative(mode));
  bool setSunlight(bool enabled) => _queue(_setSunlightNative(enabled ? 1 : 0));
  bool setSilky(bool enabled) => _queue(_setSilkyNative(enabled ? 1 : 0));
  bool setVideoEnhancement(bool enabled) =>
      _queue(_setVideoNative(enabled ? 1 : 0));
  bool setDolbyVision(bool enabled) => _queue(_setDolbyNative(enabled ? 1 : 0));
  bool setPerformanceProfile(int profile) {
    if (_latest.performanceProfile != profile) {
      _latest = RodinBackendSnapshot(
        ready: _latest.ready,
        actionState: _latest.actionState,
        chargingWriteState: _latest.chargingWriteState,
        chargingMode: _latest.chargingMode,
        batteryCapacity: _latest.batteryCapacity,
        batteryTempTenthsC: _latest.batteryTempTenthsC,
        batteryVoltageUv: _latest.batteryVoltageUv,
        batteryCurrentUa: _latest.batteryCurrentUa,
        batteryStatus: _latest.batteryStatus,
        batteryHealth: _latest.batteryHealth,
        usbOnline: _latest.usbOnline,
        usbType: _latest.usbType,
        cpuOnlineMask: _latest.cpuOnlineMask,
        cpuFreqKhz: _latest.cpuFreqKhz,
        cpuGovernor0: _latest.cpuGovernor0,
        cpuGovernor4: _latest.cpuGovernor4,
        cpuGovernor7: _latest.cpuGovernor7,
        gpuGovernor: switch (profile) {
          0 => 0, // OEM dummy
          1 => 3, // simple_ondemand
          2 => 1, // powersave
          3 => 2, // performance
          _ => _latest.gpuGovernor,
        },
        ufsScheduler: _latest.ufsScheduler,
        touchHal: _latest.touchHal,
        displayHal: _latest.displayHal,
        touchState: _latest.touchState,
        displayColor: _latest.displayColor,
        displayTemp: _latest.displayTemp,
        sunlight: _latest.sunlight,
        silky: _latest.silky,
        video: _latest.video,
        dolby: _latest.dolby,
        performanceProfile: profile,
      );
      if (!_controller.isClosed) {
        _controller.add(_latest);
      }
    }
    return _queue(_setPerformanceNative(profile));
  }

  bool setCpuGovernor(int policy, int code) =>
      _queue(_setCpuGovernorNative(policy, code));
  bool setGpuGovernor(int code) => _queue(_setGpuGovernorNative(code));
  bool setUfsScheduler(int code) => _queue(_setUfsSchedulerNative(code));
  bool openSupportLink(int code) {
    if (!_started) return false;
    return _openSupportLinkNative(code) == 1;
  }

  bool setBackIntercept(bool enabled) {
    if (!_started) return false;
    return _setBackInterceptNative(enabled ? 1 : 0) == 1;
  }

  bool consumeBackRequest() {
    if (!_started) return false;
    return _consumeBackRequestNative() == 1;
  }

  int extendedValue(int key) {
    if (!_started || _lib == null) return -1;
    return _backendGetNative(key);
  }

  bool setExtendedOperation(int op, int a, [int b = 0]) {
    if (!_started || _lib == null) return false;
    final bool res = _queue(_backendSetNative(op, a, b));
    refresh();
    return res;
  }

  bool setDoubleTapWake(bool enabled) =>
      setExtendedOperation(1, enabled ? 1 : 0);

  bool setExpertGamut(int gamut) => setExtendedOperation(2, gamut);

  bool setExpertChannel(int channel, int value) =>
      setExtendedOperation(3, channel, value);

  bool resetExpertDisplay() => setExtendedOperation(4, 0);

  bool setPerAppPerformance(bool enabled) =>
      setExtendedOperation(5, enabled ? 1 : 0);

  bool assignLastAppProfile(int profile) => setExtendedOperation(6, profile);

  bool setCpuManualMode(bool enabled) =>
      setExtendedOperation(7, enabled ? 1 : 0);

  bool setCpuCoreOnline(int cpu, bool online) {
    if (cpu < 1 || cpu > 7) return false;
    return setExtendedOperation(8, cpu, online ? 1 : 0);
  }

  bool setDisplayResolution(int width, int height, [int density = 0]) {
    if (width <= 0 || height <= 0 || (width == 1220 && height == 2712)) {
      return resetDisplayResolution();
    }
    final int detectedDensity = extendedValue(78);
    final int nativeDensity = detectedDensity > 0 ? detectedDensity : 520;
    final int safeDensity = density > 0
        ? density
        : ((nativeDensity * width + 610) ~/ 1220);
    return setExtendedOperation(
      9,
      width,
      (height << 16) | (safeDensity & 0xFFFF),
    );
  }

  bool resetDisplayResolution() => setExtendedOperation(9, 0, 0);

  bool setZramSize(int sizeMb) => setExtendedOperation(10, sizeMb);

  bool setZramAlgorithm(int algCode) => setExtendedOperation(11, algCode);

  bool setZramSwappiness(int swappiness) =>
      setExtendedOperation(12, swappiness);

  bool compactZram() => setExtendedOperation(13, 0);

  bool setGpuUncap(bool uncap) => setExtendedOperation(14, uncap ? 1 : 0);

  bool setGpuMinFreq(int mhz) => setExtendedOperation(15, mhz);

  bool setGpuMaxFreq(int mhz) => setExtendedOperation(16, mhz);

  bool setGpuDevfreqGovernor(int code) => setExtendedOperation(17, code);

  bool setGpuGedBoost(bool boost) => setExtendedOperation(18, boost ? 1 : 0);

  bool setCpuClusterMinFreq(int policy, int mhz) =>
      setExtendedOperation(19, policy, mhz);

  bool setCpuClusterMaxFreq(int policy, int mhz) =>
      setExtendedOperation(20, policy, mhz);

  bool setCpuClusterFreqRange(int policy, int minMhz, int maxMhz) {
    return setExtendedOperation(21, policy, (minMhz << 16) | (maxMhz & 0xFFFF));
  }

  bool resetCpuClusterFreqRange(int policy) => setExtendedOperation(23, policy);

  List<int> cpuAvailableFrequencies(int policy) {
    if (!_started || _lib == null || !const <int>{0, 4, 7}.contains(policy)) {
      return const <int>[];
    }

    final List<int>? cached = _cpuFrequencyTables[policy];
    if (cached != null && cached.isNotEmpty) return cached;

    final int count = _cpuAvailableCountNative(policy).clamp(0, 128).toInt();
    final List<int> frequencies = <int>[];
    for (int index = 0; index < count; index++) {
      final int mhz = _cpuAvailableFreqNative(policy, index);
      if (mhz > 0) frequencies.add(mhz);
    }
    final List<int> immutable = List<int>.unmodifiable(frequencies);
    if (immutable.isNotEmpty) _cpuFrequencyTables[policy] = immutable;
    return immutable;
  }

  int cpuTargetMinFrequency(int policy) => switch (policy) {
    0 => extendedValue(53),
    4 => extendedValue(55),
    7 => extendedValue(57),
    _ => -1,
  };

  int cpuTargetMaxFrequency(int policy) => switch (policy) {
    0 => extendedValue(54),
    4 => extendedValue(56),
    7 => extendedValue(58),
    _ => -1,
  };

  int cpuLiveMinFrequency(int policy) => switch (policy) {
    0 => extendedValue(68),
    4 => extendedValue(70),
    7 => extendedValue(72),
    _ => -1,
  };

  int cpuLiveMaxFrequency(int policy) => switch (policy) {
    0 => extendedValue(69),
    4 => extendedValue(71),
    7 => extendedValue(73),
    _ => -1,
  };

  int cpuFrequencyDrift(int policy) => switch (policy) {
    0 => extendedValue(75),
    4 => extendedValue(76),
    7 => extendedValue(77),
    _ => -1,
  };

  bool setGpuPowerPolicy(int policyCode) =>
      setExtendedOperation(22, policyCode);

  bool refreshInstalledApps() {
    if (!_started || _lib == null) return false;
    return _appsRefreshNative() == 1;
  }

  int installedAppsRevision() {
    if (!_started || _lib == null) return -1;
    return _appsRevisionNative();
  }

  int installedAppsCount() {
    if (!_started || _lib == null) return 0;
    return _appsCountNative().clamp(0, 4096).toInt();
  }

  List<RodinInstalledApp> installedApps() {
    if (!_started || _lib == null) {
      return const <RodinInstalledApp>[];
    }

    final int length = _appsBlobLenNative().clamp(0, 1 << 20).toInt();

    if (length <= 0) {
      return const <RodinInstalledApp>[];
    }

    final List<int> bytes = List<int>.filled(length, 0);

    for (int offset = 0; offset < length; offset++) {
      final int value = _appsBlobByteNative(offset);

      if (value < 0 || value > 255) {
        return const <RodinInstalledApp>[];
      }

      bytes[offset] = value;
    }

    final String raw = utf8.decode(bytes, allowMalformed: true);

    final List<RodinInstalledApp> apps = <RodinInstalledApp>[];
    final List<String> rows = const LineSplitter().convert(raw);

    for (int index = 0; index < rows.length; index++) {
      final List<String> fields = rows[index].split('\t');

      if (fields.length < 3) {
        continue;
      }

      final String packageName = fields[0].trim();
      final String label = fields[1].trim();
      final bool system = fields[2].trim() == '1';
      final String iconPath = fields.length >= 4 ? fields[3].trim() : '';

      if (packageName.isEmpty) {
        continue;
      }

      apps.add(
        RodinInstalledApp(
          index: index,
          packageName: packageName,
          label: label.isEmpty ? packageName : label,
          system: system,
          iconPath: iconPath,
        ),
      );
    }

    return List<RodinInstalledApp>.unmodifiable(apps);
  }

  int installedAppProfile(int index) {
    if (!_started || _lib == null || index < 0) return -1;
    return _appProfileNative(index);
  }

  bool setInstalledAppProfile(int index, int profile) {
    if (!_started ||
        _lib == null ||
        index < 0 ||
        !const <int>{-1, 0, 1, 2, 3}.contains(profile)) {
      return false;
    }

    return _queue(_setAppProfileNative(index, profile));
  }

  int activeInstalledAppIndex() {
    if (!_started || _lib == null) return -1;
    return _activeAppIndexNative();
  }

  int photoPermissionState() {
    if (!_started) return 0;
    return _photoPermissionStateNative();
  }

  bool requestPhotoPermission() {
    if (!_started) return false;
    return _requestPhotoPermissionNative() == 1;
  }

  void refresh() {
    if (_started) _refreshNative();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  bool haptic(int kind) {
    if (!_started || kind < 1 || kind > 9) {
      return false;
    }

    return _hapticNative(kind) == 1;
  }
}
