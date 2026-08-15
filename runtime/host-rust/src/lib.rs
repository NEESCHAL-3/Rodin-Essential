use core::ffi::{c_char, c_int, c_void};
use core::ptr;
use core::slice;
use std::ffi::{CStr, CString};
use std::fs::{create_dir_all, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

include!("flutter_layout.rs");

const ANDROID_LOG_INFO: c_int = 4;
const WINDOW_FORMAT_RGBA_8888: c_int = 1;
const AASSET_MODE_STREAMING: c_int = 2;
const FLUTTER_ENGINE_VERSION: usize = 1;
const FLUTTER_RENDERER_SOFTWARE: i32 = 1;
const RTLD_NOW: c_int = 2;

#[repr(C)]
pub struct ARect {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
}

#[repr(C)]
pub struct ANativeWindowBuffer {
    width: i32,
    height: i32,
    stride: i32,
    format: i32,
    bits: *mut c_void,
    reserved: [u32; 6],
}

#[repr(C)]
pub struct ANativeActivityCallbacks {
    on_start: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    on_resume: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    on_save_instance_state:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut usize) -> *mut c_void>,
    on_pause: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    on_stop: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    on_destroy: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    on_window_focus_changed: Option<unsafe extern "C" fn(*mut ANativeActivity, c_int)>,
    on_native_window_created:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut ANativeWindow)>,
    on_native_window_resized:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut ANativeWindow)>,
    on_native_window_redraw_needed:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut ANativeWindow)>,
    on_native_window_destroyed:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut ANativeWindow)>,
    on_input_queue_created:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut AInputQueue)>,
    on_input_queue_destroyed:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *mut AInputQueue)>,
    on_content_rect_changed:
        Option<unsafe extern "C" fn(*mut ANativeActivity, *const ARect)>,
    on_configuration_changed: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
    on_low_memory: Option<unsafe extern "C" fn(*mut ANativeActivity)>,
}

#[repr(C)]
pub struct ANativeActivity {
    callbacks: *mut ANativeActivityCallbacks,
    vm: *mut c_void,
    env: *mut c_void,
    clazz: *mut c_void,
    internal_data_path: *const c_char,
    external_data_path: *const c_char,
    sdk_version: i32,
    instance: *mut c_void,
    asset_manager: *mut AAssetManager,
    obb_path: *const c_char,
}

#[repr(C)]
pub struct ANativeWindow {
    _private: [u8; 0],
}

#[repr(C)]
pub struct AInputQueue {
    _private: [u8; 0],
}

#[repr(C)]
pub struct AAssetManager {
    _private: [u8; 0],
}

#[repr(C)]
pub struct AAsset {
    _private: [u8; 0],
}

#[repr(C)]
pub struct AConfiguration {
    _private: [u8; 0],
}

struct HostState {
    window: Mutex<usize>,
    engine: Mutex<usize>,
    app_handle: Mutex<usize>,
    first_frame_logged: AtomicBool,
}

impl HostState {
    fn new() -> Self {
        Self {
            window: Mutex::new(0),
            engine: Mutex::new(0),
            app_handle: Mutex::new(0),
            first_frame_logged: AtomicBool::new(false),
        }
    }
}

#[link(name = "log")]
unsafe extern "C" {
    fn __android_log_write(
        prio: c_int,
        tag: *const c_char,
        text: *const c_char,
    ) -> c_int;
}

#[link(name = "android")]
unsafe extern "C" {
    fn ANativeWindow_acquire(window: *mut ANativeWindow);
    fn ANativeWindow_release(window: *mut ANativeWindow);
    fn ANativeWindow_getWidth(window: *mut ANativeWindow) -> i32;
    fn ANativeWindow_getHeight(window: *mut ANativeWindow) -> i32;

    fn ANativeWindow_setBuffersGeometry(
        window: *mut ANativeWindow,
        width: i32,
        height: i32,
        format: i32,
    ) -> i32;

    fn ANativeWindow_lock(
        window: *mut ANativeWindow,
        out_buffer: *mut ANativeWindowBuffer,
        in_out_dirty_bounds: *mut ARect,
    ) -> i32;

    fn ANativeWindow_unlockAndPost(window: *mut ANativeWindow) -> i32;

    fn AAssetManager_open(
        manager: *mut AAssetManager,
        filename: *const c_char,
        mode: c_int,
    ) -> *mut AAsset;

    fn AAsset_getLength64(asset: *mut AAsset) -> i64;
    fn AAsset_read(asset: *mut AAsset, buf: *mut c_void, count: usize) -> c_int;
    fn AAsset_close(asset: *mut AAsset);

    fn AConfiguration_new() -> *mut AConfiguration;
    fn AConfiguration_delete(config: *mut AConfiguration);
    fn AConfiguration_fromAssetManager(
        config: *mut AConfiguration,
        manager: *mut AAssetManager,
    );
    fn AConfiguration_getDensity(config: *mut AConfiguration) -> i32;
}

#[link(name = "dl")]
unsafe extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    fn dlerror() -> *const c_char;
}

#[link(name = "flutter_engine")]
unsafe extern "C" {
    fn FlutterEngineRun(
        version: usize,
        config: *const c_void,
        args: *const c_void,
        user_data: *mut c_void,
        engine_out: *mut *mut c_void,
    ) -> c_int;

    fn FlutterEngineShutdown(engine: *mut c_void) -> c_int;

    fn FlutterEngineSendWindowMetricsEvent(
        engine: *mut c_void,
        event: *const c_void,
    ) -> c_int;

    fn FlutterEngineScheduleFrame(engine: *mut c_void) -> c_int;

    fn FlutterEngineNotifyLowMemoryWarning(engine: *mut c_void) -> c_int;

    fn FlutterEngineRunsAOTCompiledDartCode() -> bool;
}

fn log_str(message: &str) {
    static TAG: &[u8] = b"RodinEssential\0";

    let clean = message.replace('\0', " ");
    if let Ok(text) = CString::new(clean) {
        unsafe {
            __android_log_write(
                ANDROID_LOG_INFO,
                TAG.as_ptr().cast(),
                text.as_ptr(),
            );
        }
    }
}

fn c_string(pointer: *const c_char) -> String {
    if pointer.is_null() {
        return String::new();
    }

    unsafe { CStr::from_ptr(pointer).to_string_lossy().into_owned() }
}

fn dl_error_string() -> String {
    unsafe {
        let error = dlerror();
        if error.is_null() {
            "unknown dlopen/dlsym error".to_string()
        } else {
            CStr::from_ptr(error).to_string_lossy().into_owned()
        }
    }
}

fn put_usize(buffer: &mut [u8], offset: usize, value: usize) {
    if offset + core::mem::size_of::<usize>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(
                buffer.as_mut_ptr().add(offset).cast::<usize>(),
                value,
            );
        }
    }
}

fn put_i32(buffer: &mut [u8], offset: usize, value: i32) {
    if offset + core::mem::size_of::<i32>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(
                buffer.as_mut_ptr().add(offset).cast::<i32>(),
                value,
            );
        }
    }
}

fn put_u64(buffer: &mut [u8], offset: usize, value: u64) {
    if offset + core::mem::size_of::<u64>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(
                buffer.as_mut_ptr().add(offset).cast::<u64>(),
                value,
            );
        }
    }
}

fn put_i64(buffer: &mut [u8], offset: usize, value: i64) {
    if offset + core::mem::size_of::<i64>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(
                buffer.as_mut_ptr().add(offset).cast::<i64>(),
                value,
            );
        }
    }
}

fn put_f64(buffer: &mut [u8], offset: usize, value: f64) {
    if offset + core::mem::size_of::<f64>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(
                buffer.as_mut_ptr().add(offset).cast::<f64>(),
                value,
            );
        }
    }
}

fn put_bool(buffer: &mut [u8], offset: usize, value: bool) {
    if offset < buffer.len() {
        buffer[offset] = u8::from(value);
    }
}

fn read_asset(
    manager: *mut AAssetManager,
    name: &str,
) -> Result<Vec<u8>, String> {
    let c_name = CString::new(name)
        .map_err(|_| format!("invalid asset name: {name}"))?;

    let asset = unsafe {
        AAssetManager_open(
            manager,
            c_name.as_ptr(),
            AASSET_MODE_STREAMING,
        )
    };

    if asset.is_null() {
        return Err(format!("asset not found: {name}"));
    }

    let length = unsafe { AAsset_getLength64(asset) };
    if length < 0 {
        unsafe { AAsset_close(asset) };
        return Err(format!("invalid asset length: {name}"));
    }

    let mut data = vec![0u8; length as usize];
    let mut offset = 0usize;

    while offset < data.len() {
        let read = unsafe {
            AAsset_read(
                asset,
                data.as_mut_ptr().add(offset).cast(),
                data.len() - offset,
            )
        };

        if read <= 0 {
            break;
        }

        offset += read as usize;
    }

    unsafe { AAsset_close(asset) };

    data.truncate(offset);

    if offset != length as usize {
        return Err(format!(
            "short asset read: {name} expected={} got={offset}",
            length
        ));
    }

    Ok(data)
}

fn write_file(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        create_dir_all(parent)
            .map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
    }

    let mut file = File::create(path)
        .map_err(|e| format!("create {}: {e}", path.display()))?;

    file.write_all(data)
        .map_err(|e| format!("write {}: {e}", path.display()))
}

fn prepare_runtime_files(
    activity: *mut ANativeActivity,
) -> Result<(CString, CString, CString), String> {
    if activity.is_null() {
        return Err("activity is null".to_string());
    }

    let internal = unsafe { (*activity).internal_data_path };
    let manager = unsafe { (*activity).asset_manager };

    if internal.is_null() || manager.is_null() {
        return Err("NativeActivity paths/assets unavailable".to_string());
    }

    let base = PathBuf::from(c_string(internal)).join("rodin_flutter");
    let assets_dir = base.join("flutter_assets");
    let cache_dir = base.join("cache");

    create_dir_all(&assets_dir)
        .map_err(|e| format!("mkdir {}: {e}", assets_dir.display()))?;
    create_dir_all(&cache_dir)
        .map_err(|e| format!("mkdir {}: {e}", cache_dir.display()))?;

    let index_bytes = read_asset(manager, "flutter_assets.index")?;
    let index = String::from_utf8(index_bytes)
        .map_err(|e| format!("flutter_assets.index UTF-8: {e}"))?;

    let mut copied = 0usize;

    for raw in index.lines() {
        let relative = raw.trim();

        if relative.is_empty() {
            continue;
        }

        let asset_name = format!("flutter_assets/{relative}");
        let data = read_asset(manager, &asset_name)?;
        write_file(&assets_dir.join(relative), &data)?;
        copied += 1;
    }

    let icu = read_asset(manager, "icudtl.dat")?;
    let icu_path = base.join("icudtl.dat");
    write_file(&icu_path, &icu)?;

    log_str(&format!(
        "runtime assets extracted: files={copied} icu={} bytes",
        icu.len()
    ));

    let assets_c = CString::new(assets_dir.to_string_lossy().as_bytes())
        .map_err(|_| "assets path contains NUL".to_string())?;
    let icu_c = CString::new(icu_path.to_string_lossy().as_bytes())
        .map_err(|_| "ICU path contains NUL".to_string())?;
    let cache_c = CString::new(cache_dir.to_string_lossy().as_bytes())
        .map_err(|_| "cache path contains NUL".to_string())?;

    Ok((assets_c, icu_c, cache_c))
}

fn pixel_ratio(activity: *mut ANativeActivity) -> f64 {
    if activity.is_null() {
        return 1.0;
    }

    unsafe {
        let config = AConfiguration_new();

        if config.is_null() {
            return 1.0;
        }

        AConfiguration_fromAssetManager(config, (*activity).asset_manager);
        let density = AConfiguration_getDensity(config);
        AConfiguration_delete(config);

        if density > 0 && density != 0xffff {
            density as f64 / 160.0
        } else {
            1.0
        }
    }
}

unsafe fn symbol(
    handle: *mut c_void,
    name: &'static [u8],
) -> Result<*const u8, String> {
    let symbol = unsafe { dlsym(handle, name.as_ptr().cast()) };

    if symbol.is_null() {
        Err(format!(
            "dlsym {} failed: {}",
            String::from_utf8_lossy(&name[..name.len().saturating_sub(1)]),
            dl_error_string()
        ))
    } else {
        Ok(symbol.cast())
    }
}

unsafe extern "C" fn flutter_log_callback(
    tag: *const c_char,
    message: *const c_char,
    _user_data: *mut c_void,
) {
    let tag = c_string(tag);
    let message = c_string(message);
    log_str(&format!("flutter[{tag}] {message}"));
}

unsafe extern "C" fn software_present(
    user_data: *mut c_void,
    allocation: *const c_void,
    row_bytes: usize,
    height: usize,
) -> bool {
    if user_data.is_null() || allocation.is_null() {
        return false;
    }

    let state = unsafe { &*(user_data.cast::<HostState>()) };

    let window_value = {
        let guard = match state.window.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };

        let value = *guard;
        if value != 0 {
            unsafe { ANativeWindow_acquire(value as *mut ANativeWindow) };
        }
        value
    };

    if window_value == 0 {
        return true;
    }

    let window = window_value as *mut ANativeWindow;

    let mut buffer = ANativeWindowBuffer {
        width: 0,
        height: 0,
        stride: 0,
        format: 0,
        bits: ptr::null_mut(),
        reserved: [0; 6],
    };

    let lock_result = unsafe {
        ANativeWindow_lock(window, &mut buffer, ptr::null_mut())
    };

    if lock_result != 0 || buffer.bits.is_null() {
        unsafe { ANativeWindow_release(window) };
        log_str(&format!("software present lock failed rc={lock_result}"));
        return false;
    }

    let dest_height = buffer.height.max(0) as usize;
    let dest_width = buffer.width.max(0) as usize;
    let dest_stride = buffer.stride.max(0) as usize;

    let rows = height.min(dest_height);
    let bytes_per_dest_row = dest_stride.saturating_mul(4);
    let visible_dest_bytes = dest_width.saturating_mul(4);
    let copy_bytes = row_bytes.min(visible_dest_bytes);

    let source = allocation.cast::<u8>();
    let destination = buffer.bits.cast::<u8>();

    for y in 0..rows {
        unsafe {
            ptr::copy_nonoverlapping(
                source.add(y.saturating_mul(row_bytes)),
                destination.add(y.saturating_mul(bytes_per_dest_row)),
                copy_bytes,
            );
        }
    }

    let post_result = unsafe { ANativeWindow_unlockAndPost(window) };
    unsafe { ANativeWindow_release(window) };

    if post_result != 0 {
        log_str(&format!("software present post failed rc={post_result}"));
        return false;
    }

    if !state.first_frame_logged.swap(true, Ordering::AcqRel) {
        log_str(&format!(
            "FLUTTER_FIRST_FRAME=PASS row_bytes={row_bytes} height={height}"
        ));
    }

    true
}

unsafe fn send_metrics(
    activity: *mut ANativeActivity,
    state: *mut HostState,
) {
    if activity.is_null() || state.is_null() {
        return;
    }

    let engine_value = {
        let guard = match unsafe { &*state }.engine.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard
    };

    if engine_value == 0 {
        return;
    }

    let window_value = {
        let guard = match unsafe { &*state }.window.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard
    };

    if window_value == 0 {
        return;
    }

    let window = window_value as *mut ANativeWindow;
    let width = unsafe { ANativeWindow_getWidth(window) }.max(0) as usize;
    let height = unsafe { ANativeWindow_getHeight(window) }.max(0) as usize;

    if width == 0 || height == 0 {
        return;
    }

    let ratio = pixel_ratio(activity);

    let mut metrics = vec![0u8; FLUTTER_WINDOW_METRICS_SIZE];
    put_usize(
        &mut metrics,
        OFF_METRICS_STRUCT_SIZE,
        FLUTTER_WINDOW_METRICS_SIZE,
    );
    put_usize(&mut metrics, OFF_METRICS_WIDTH, width);
    put_usize(&mut metrics, OFF_METRICS_HEIGHT, height);
    put_f64(&mut metrics, OFF_METRICS_PIXEL_RATIO, ratio);
    put_u64(&mut metrics, OFF_METRICS_DISPLAY_ID, 0);
    put_i64(&mut metrics, OFF_METRICS_VIEW_ID, 0);
    put_bool(&mut metrics, OFF_METRICS_HAS_CONSTRAINTS, false);

    let result = unsafe {
        FlutterEngineSendWindowMetricsEvent(
            engine_value as *mut c_void,
            metrics.as_ptr().cast(),
        )
    };

    log_str(&format!(
        "window metrics width={width} height={height} ratio={ratio:.3} rc={result}"
    ));
}

unsafe fn start_flutter(
    activity: *mut ANativeActivity,
    state: *mut HostState,
) -> Result<(), String> {
    if activity.is_null() || state.is_null() {
        return Err("start_flutter null state".to_string());
    }

    {
        let guard = match unsafe { &*state }.engine.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };

        if *guard != 0 {
            return Ok(());
        }
    }

    if !unsafe { FlutterEngineRunsAOTCompiledDartCode() } {
        return Err("custom Flutter engine is not running AOT code".to_string());
    }

    let (assets_path, icu_path, cache_path) =
        prepare_runtime_files(activity)?;

    static LIBAPP: &[u8] = b"libapp.so\0";

    let app_handle = unsafe {
        dlopen(LIBAPP.as_ptr().cast(), RTLD_NOW)
    };

    if app_handle.is_null() {
        return Err(format!("dlopen(libapp.so) failed: {}", dl_error_string()));
    }

    let vm_data = match unsafe {
        symbol(app_handle, b"_kDartVmSnapshotData\0")
    } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let vm_instructions = match unsafe {
        symbol(app_handle, b"_kDartVmSnapshotInstructions\0")
    } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let isolate_data = match unsafe {
        symbol(app_handle, b"_kDartIsolateSnapshotData\0")
    } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let isolate_instructions = match unsafe {
        symbol(app_handle, b"_kDartIsolateSnapshotInstructions\0")
    } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let mut renderer = vec![0u8; FLUTTER_RENDERER_CONFIG_SIZE];
    put_i32(
        &mut renderer,
        OFF_RENDERER_TYPE,
        FLUTTER_RENDERER_SOFTWARE,
    );

    let software_base = OFF_RENDERER_SOFTWARE;

    put_usize(
        &mut renderer,
        software_base + OFF_SOFTWARE_STRUCT_SIZE,
        FLUTTER_SOFTWARE_RENDERER_CONFIG_SIZE,
    );

    put_usize(
        &mut renderer,
        software_base + OFF_SOFTWARE_PRESENT,
        software_present as usize,
    );

    let mut project = vec![0u8; FLUTTER_PROJECT_ARGS_SIZE];

    put_usize(
        &mut project,
        OFF_PROJECT_STRUCT_SIZE,
        FLUTTER_PROJECT_ARGS_SIZE,
    );

    put_usize(
        &mut project,
        OFF_PROJECT_ASSETS_PATH,
        assets_path.as_ptr() as usize,
    );

    put_usize(
        &mut project,
        OFF_PROJECT_ICU_DATA_PATH,
        icu_path.as_ptr() as usize,
    );

    put_usize(&mut project, OFF_PROJECT_VM_DATA, vm_data as usize);
    put_usize(&mut project, OFF_PROJECT_VM_DATA_SIZE, 0);

    put_usize(
        &mut project,
        OFF_PROJECT_VM_INSTRUCTIONS,
        vm_instructions as usize,
    );
    put_usize(
        &mut project,
        OFF_PROJECT_VM_INSTRUCTIONS_SIZE,
        0,
    );

    put_usize(
        &mut project,
        OFF_PROJECT_ISOLATE_DATA,
        isolate_data as usize,
    );
    put_usize(
        &mut project,
        OFF_PROJECT_ISOLATE_DATA_SIZE,
        0,
    );

    put_usize(
        &mut project,
        OFF_PROJECT_ISOLATE_INSTRUCTIONS,
        isolate_instructions as usize,
    );
    put_usize(
        &mut project,
        OFF_PROJECT_ISOLATE_INSTRUCTIONS_SIZE,
        0,
    );

    put_usize(
        &mut project,
        OFF_PROJECT_PERSISTENT_CACHE_PATH,
        cache_path.as_ptr() as usize,
    );

    put_bool(&mut project, OFF_PROJECT_SHUTDOWN_VM, true);

    put_usize(
        &mut project,
        OFF_PROJECT_LOG_CALLBACK,
        flutter_log_callback as usize,
    );

    static DART_LOG_TAG: &[u8] = b"RodinDart\0";
    put_usize(
        &mut project,
        OFF_PROJECT_LOG_TAG,
        DART_LOG_TAG.as_ptr() as usize,
    );

    put_bool(&mut project, OFF_PROJECT_ENABLE_WIDE_GAMUT, false);

    // Phase 6 uses Flutter's software renderer for first-frame proof.
    // Explicitly disable Impeller so DisplayList text is generated for
    // the Skia/software canvas instead of Impeller.
    static EXECUTABLE_NAME: &[u8] = b"rodin_essential\0";
    static DISABLE_IMPELLER: &[u8] = b"--enable-impeller=false\0";

    let command_line_args: [*const c_char; 2] = [
        EXECUTABLE_NAME.as_ptr().cast(),
        DISABLE_IMPELLER.as_ptr().cast(),
    ];

    put_i32(
        &mut project,
        OFF_PROJECT_COMMAND_LINE_ARGC,
        command_line_args.len() as i32,
    );

    put_usize(
        &mut project,
        OFF_PROJECT_COMMAND_LINE_ARGV,
        command_line_args.as_ptr() as usize,
    );

    log_str("software proof flag: --enable-impeller=false");

    let mut engine: *mut c_void = ptr::null_mut();

    log_str("starting FlutterEngineRun");

    let result = unsafe {
        FlutterEngineRun(
            FLUTTER_ENGINE_VERSION,
            renderer.as_ptr().cast(),
            project.as_ptr().cast(),
            state.cast(),
            &mut engine,
        )
    };

    if result != 0 || engine.is_null() {
        unsafe { dlclose(app_handle) };
        return Err(format!(
            "FlutterEngineRun failed rc={result} engine={engine:p}"
        ));
    }

    {
        let mut guard = match unsafe { &*state }.app_handle.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard = app_handle as usize;
    }

    {
        let mut guard = match unsafe { &*state }.engine.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard = engine as usize;
    }

    log_str("FLUTTER_ENGINE_RUN=PASS");

    unsafe { send_metrics(activity, state) };

    let schedule = unsafe { FlutterEngineScheduleFrame(engine) };
    log_str(&format!("FlutterEngineScheduleFrame rc={schedule}"));

    Ok(())
}

unsafe fn replace_window(
    state: *mut HostState,
    window: *mut ANativeWindow,
) {
    if state.is_null() {
        return;
    }

    if !window.is_null() {
        unsafe {
            ANativeWindow_acquire(window);
            ANativeWindow_setBuffersGeometry(
                window,
                0,
                0,
                WINDOW_FORMAT_RGBA_8888,
            );
        }
    }

    let old = {
        let mut guard = match unsafe { &*state }.window.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };

        let old = *guard;
        *guard = window as usize;
        old
    };

    if old != 0 {
        unsafe { ANativeWindow_release(old as *mut ANativeWindow) };
    }
}

unsafe extern "C" fn on_start(_: *mut ANativeActivity) {
    log_str("onStart");
}

unsafe extern "C" fn on_resume(_: *mut ANativeActivity) {
    log_str("onResume");
}

unsafe extern "C" fn on_pause(_: *mut ANativeActivity) {
    log_str("onPause");
}

unsafe extern "C" fn on_stop(_: *mut ANativeActivity) {
    log_str("onStop");
}

unsafe extern "C" fn on_window_focus_changed(
    _: *mut ANativeActivity,
    focused: c_int,
) {
    log_str(&format!("window focus={focused}"));
}

unsafe extern "C" fn on_window_created(
    activity: *mut ANativeActivity,
    window: *mut ANativeWindow,
) {
    log_str("native window created");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    unsafe { replace_window(state, window) };

    match unsafe { start_flutter(activity, state) } {
        Ok(()) => unsafe { send_metrics(activity, state) },
        Err(error) => log_str(&format!("FLUTTER_START=FAIL {error}")),
    }
}

unsafe extern "C" fn on_window_resized(
    activity: *mut ANativeActivity,
    window: *mut ANativeWindow,
) {
    log_str("native window resized");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    unsafe { replace_window(state, window) };
    unsafe { send_metrics(activity, state) };
}

unsafe extern "C" fn on_window_redraw(
    activity: *mut ANativeActivity,
    _: *mut ANativeWindow,
) {
    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };
    if state.is_null() {
        return;
    }

    let engine = {
        let guard = match unsafe { &*state }.engine.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard
    };

    if engine != 0 {
        unsafe { FlutterEngineScheduleFrame(engine as *mut c_void) };
    }
}

unsafe extern "C" fn on_window_destroyed(
    activity: *mut ANativeActivity,
    _: *mut ANativeWindow,
) {
    log_str("native window destroyed");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };
    unsafe { replace_window(state, ptr::null_mut()) };
}

unsafe extern "C" fn on_low_memory(activity: *mut ANativeActivity) {
    log_str("onLowMemory");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };
    if state.is_null() {
        return;
    }

    let engine = {
        let guard = match unsafe { &*state }.engine.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        *guard
    };

    if engine != 0 {
        unsafe {
            FlutterEngineNotifyLowMemoryWarning(engine as *mut c_void);
        }
    }
}

unsafe extern "C" fn on_destroy(activity: *mut ANativeActivity) {
    log_str("onDestroy");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    if state.is_null() {
        return;
    }

    let engine = {
        let mut guard = match unsafe { &*state }.engine.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        let engine = *guard;
        *guard = 0;
        engine
    };

    if engine != 0 {
        let result = unsafe {
            FlutterEngineShutdown(engine as *mut c_void)
        };
        log_str(&format!("FlutterEngineShutdown rc={result}"));
    }

    unsafe { replace_window(state, ptr::null_mut()) };

    let app_handle = {
        let mut guard = match unsafe { &*state }.app_handle.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        let handle = *guard;
        *guard = 0;
        handle
    };

    if app_handle != 0 {
        unsafe {
            dlclose(app_handle as *mut c_void);
        }
    }

    unsafe {
        (*activity).instance = ptr::null_mut();
        drop(Box::from_raw(state));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ANativeActivity_onCreate(
    activity: *mut ANativeActivity,
    _saved_state: *mut c_void,
    _saved_state_size: usize,
) {
    log_str("ANativeActivity_onCreate");

    if activity.is_null() {
        log_str("activity pointer is null");
        return;
    }

    let callbacks = unsafe { (*activity).callbacks };

    if callbacks.is_null() {
        log_str("callback table is null");
        return;
    }

    let state = Box::new(HostState::new());
    let state_ptr = Box::into_raw(state);

    unsafe {
        (*activity).instance = state_ptr.cast();

        (*callbacks).on_start = Some(on_start);
        (*callbacks).on_resume = Some(on_resume);
        (*callbacks).on_pause = Some(on_pause);
        (*callbacks).on_stop = Some(on_stop);
        (*callbacks).on_destroy = Some(on_destroy);
        (*callbacks).on_window_focus_changed = Some(on_window_focus_changed);
        (*callbacks).on_native_window_created = Some(on_window_created);
        (*callbacks).on_native_window_resized = Some(on_window_resized);
        (*callbacks).on_native_window_redraw_needed = Some(on_window_redraw);
        (*callbacks).on_native_window_destroyed = Some(on_window_destroyed);
        (*callbacks).on_low_memory = Some(on_low_memory);
    }

    log_str("native callbacks installed");
}
