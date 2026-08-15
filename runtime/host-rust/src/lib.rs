use core::ffi::{c_char, c_int, c_void};
use core::ptr;
use core::slice;

const ANDROID_LOG_INFO: c_int = 4;
const WINDOW_FORMAT_RGBA_8888: c_int = 1;

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
    asset_manager: *mut c_void,
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

#[link(name = "log")]
unsafe extern "C" {
    fn __android_log_print(
        prio: c_int,
        tag: *const c_char,
        fmt: *const c_char,
        ...
    ) -> c_int;
}

#[link(name = "android")]
unsafe extern "C" {
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
}

fn log(message: &'static [u8]) {
    static TAG: &[u8] = b"RodinEssential\0";
    static FMT: &[u8] = b"%s\0";

    unsafe {
        __android_log_print(
            ANDROID_LOG_INFO,
            TAG.as_ptr().cast(),
            FMT.as_ptr().cast(),
            message.as_ptr().cast::<c_char>(),
        );
    }
}

unsafe fn render(window: *mut ANativeWindow) {
    if window.is_null() {
        return;
    }

    let _ = unsafe {
        ANativeWindow_setBuffersGeometry(window, 0, 0, WINDOW_FORMAT_RGBA_8888)
    };

    let mut buffer = ANativeWindowBuffer {
        width: 0,
        height: 0,
        stride: 0,
        format: 0,
        bits: ptr::null_mut(),
        reserved: [0; 6],
    };

    let lock_result =
        unsafe { ANativeWindow_lock(window, &mut buffer, ptr::null_mut()) };

    if lock_result != 0 || buffer.bits.is_null() {
        log(b"window lock failed\0");
        return;
    }

    let width = buffer.width.max(0) as usize;
    let height = buffer.height.max(0) as usize;
    let stride = buffer.stride.max(0) as usize;
    let pixels = unsafe {
        slice::from_raw_parts_mut(buffer.bits.cast::<u32>(), stride.saturating_mul(height))
    };

    for y in 0..height {
        let t = if height > 1 {
            (y * 28 / (height - 1)) as u32
        } else {
            0
        };

        let r = 0x12 + t / 5;
        let g = 0x15 + t / 4;
        let b = 0x1b + t;

        let pixel = 0xff00_0000u32 | (b << 16) | (g << 8) | r;

        let row = y * stride;
        for x in 0..width {
            pixels[row + x] = pixel;
        }
    }

    let _ = unsafe { ANativeWindow_unlockAndPost(window) };
    log(b"native frame posted\0");
}

unsafe extern "C" fn on_start(_: *mut ANativeActivity) {
    log(b"onStart\0");
}

unsafe extern "C" fn on_resume(_: *mut ANativeActivity) {
    log(b"onResume\0");
}

unsafe extern "C" fn on_pause(_: *mut ANativeActivity) {
    log(b"onPause\0");
}

unsafe extern "C" fn on_stop(_: *mut ANativeActivity) {
    log(b"onStop\0");
}

unsafe extern "C" fn on_destroy(_: *mut ANativeActivity) {
    log(b"onDestroy\0");
}

unsafe extern "C" fn on_window_created(
    _: *mut ANativeActivity,
    window: *mut ANativeWindow,
) {
    log(b"native window created\0");
    unsafe { render(window) };
}

unsafe extern "C" fn on_window_resized(
    _: *mut ANativeActivity,
    window: *mut ANativeWindow,
) {
    log(b"native window resized\0");
    unsafe { render(window) };
}

unsafe extern "C" fn on_window_redraw(
    _: *mut ANativeActivity,
    window: *mut ANativeWindow,
) {
    unsafe { render(window) };
}

unsafe extern "C" fn on_window_destroyed(
    _: *mut ANativeActivity,
    _: *mut ANativeWindow,
) {
    log(b"native window destroyed\0");
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn ANativeActivity_onCreate(
    activity: *mut ANativeActivity,
    _saved_state: *mut c_void,
    _saved_state_size: usize,
) {
    log(b"ANativeActivity_onCreate\0");

    if activity.is_null() {
        log(b"activity pointer is null\0");
        return;
    }

    let callbacks = unsafe { (*activity).callbacks };

    if callbacks.is_null() {
        log(b"callback table is null\0");
        return;
    }

    unsafe {
        (*callbacks).on_start = Some(on_start);
        (*callbacks).on_resume = Some(on_resume);
        (*callbacks).on_pause = Some(on_pause);
        (*callbacks).on_stop = Some(on_stop);
        (*callbacks).on_destroy = Some(on_destroy);
        (*callbacks).on_native_window_created = Some(on_window_created);
        (*callbacks).on_native_window_resized = Some(on_window_resized);
        (*callbacks).on_native_window_redraw_needed = Some(on_window_redraw);
        (*callbacks).on_native_window_destroyed = Some(on_window_destroyed);
    }

    log(b"native callbacks installed\0");
}
