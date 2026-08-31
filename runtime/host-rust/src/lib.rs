mod backend_bridge;
use core::ffi::{c_char, c_int, c_void};
use core::ptr;
use std::ffi::{CStr, CString};
use std::fs::{File, create_dir_all};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, mpsc};
use std::thread::JoinHandle;
use std::time::Duration;

// Zero-DEX media permission bridge.
// FFI reads are atomic only; permission UI is requested from the
// NativeActivity/main choreographer thread.

static RODIN_PHOTO_ACTIVITY: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);
static RODIN_PHOTO_CHOREOGRAPHER: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);
static RODIN_PHOTO_PERMISSION_STATE: std::sync::atomic::AtomicI32 =
    std::sync::atomic::AtomicI32::new(0);
static RODIN_PHOTO_REQUEST_PENDING: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);
static RODIN_PHOTO_REQUEST_SCHEDULED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

fn rodin_photo_vm_and_object(
    activity: *mut ANativeActivity,
) -> Option<(jni::JavaVM, jni::sys::jobject, i32)> {
    if activity.is_null() {
        return None;
    }

    let (vm_raw, object_raw, sdk) = unsafe {
        (
            (*activity).vm as *mut jni::sys::JavaVM,
            (*activity).clazz as jni::sys::jobject,
            (*activity).sdk_version,
        )
    };

    if vm_raw.is_null() || object_raw.is_null() {
        return None;
    }

    let vm = unsafe { jni::JavaVM::from_raw(vm_raw) }.ok()?;
    Some((vm, object_raw, sdk))
}

fn rodin_prepare_launch_window(activity: *mut ANativeActivity) {
    let Some((vm, object_raw, _)) = rodin_photo_vm_and_object(activity) else {
        return;
    };

    let mut env = match vm.get_env() {
        Ok(env) => env,
        Err(_) => return,
    };

    let result: jni::errors::Result<bool> = env.with_local_frame(8, |env| {
        let activity_obj = unsafe { jni::objects::JObject::from_raw(object_raw) };

        let window = env
            .call_method(&activity_obj, "getWindow", "()Landroid/view/Window;", &[])?
            .l()?;

        let decor = env
            .call_method(&window, "getDecorView", "()Landroid/view/View;", &[])?
            .l()?;

        env.call_method(
            &decor,
            "setBackgroundColor",
            "(I)V",
            &[jni::objects::JValue::Int(-1)],
        )?;
        env.call_method(&decor, "invalidate", "()V", &[])?;

        env.call_method(
            &activity_obj,
            "setTranslucent",
            "(Z)Z",
            &[jni::objects::JValue::Bool(0)],
        )?
        .z()
    });

    match result {
        Ok(opaque) => log_str(&format!(
            "LAUNCH_WINDOW_PREPARED=PASS background=white opaque={opaque}"
        )),
        Err(error) => {
            let _ = env.exception_clear();
            log_str(&format!("LAUNCH_WINDOW_PREPARED=FAIL error={error}"));
        }
    }
}

fn rodin_photo_check_named(activity: *mut ANativeActivity, permission_name: &str) -> bool {
    let Some((vm, object_raw, _)) = rodin_photo_vm_and_object(activity) else {
        return false;
    };

    let mut env = match vm.get_env() {
        Ok(env) => env,
        Err(_) => return false,
    };

    let result: jni::errors::Result<bool> = env.with_local_frame(8, |env| {
        let activity_obj = unsafe { jni::objects::JObject::from_raw(object_raw) };

        let permission = env.new_string(permission_name)?;
        let permission_obj = jni::objects::JObject::from(permission);

        let grant = env
            .call_method(
                &activity_obj,
                "checkSelfPermission",
                "(Ljava/lang/String;)I",
                &[jni::objects::JValue::Object(&permission_obj)],
            )?
            .i()?;

        Ok(grant == 0)
    });

    match result {
        Ok(value) => value,
        Err(_) => {
            let _ = env.exception_clear();
            false
        }
    }
}

fn rodin_photo_compute_permission_state(activity: *mut ANativeActivity) -> i32 {
    if activity.is_null() {
        return 0;
    }

    let sdk = unsafe { (*activity).sdk_version };

    if sdk >= 33 {
        if rodin_photo_check_named(activity, "android.permission.READ_MEDIA_IMAGES") {
            return 2;
        }

        if sdk >= 34
            && rodin_photo_check_named(
                activity,
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
            )
        {
            return 1;
        }

        0
    } else if rodin_photo_check_named(activity, "android.permission.READ_EXTERNAL_STORAGE") {
        2
    } else {
        0
    }
}

fn rodin_photo_refresh_permission(activity: *mut ANativeActivity) {
    let state = rodin_photo_compute_permission_state(activity);

    RODIN_PHOTO_PERMISSION_STATE.store(state, std::sync::atomic::Ordering::Release);
}

fn rodin_photo_request_on_main(activity: *mut ANativeActivity) -> bool {
    let Some((vm, object_raw, sdk)) = rodin_photo_vm_and_object(activity) else {
        return false;
    };

    let mut env = match vm.get_env() {
        Ok(env) => env,
        Err(_) => return false,
    };

    let result: jni::errors::Result<bool> = env.with_local_frame(24, |env| {
        let activity_obj = unsafe { jni::objects::JObject::from_raw(object_raw) };

        let permissions: Vec<&str> = if sdk >= 34 {
            vec![
                "android.permission.READ_MEDIA_IMAGES",
                "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
            ]
        } else if sdk >= 33 {
            vec!["android.permission.READ_MEDIA_IMAGES"]
        } else {
            vec!["android.permission.READ_EXTERNAL_STORAGE"]
        };

        let string_class = env.find_class("java/lang/String")?;

        let array = env.new_object_array(
            permissions.len() as i32,
            string_class,
            jni::objects::JObject::null(),
        )?;

        for (index, name) in permissions.iter().enumerate() {
            let value = env.new_string(*name)?;
            env.set_object_array_element(&array, index as i32, value)?;
        }

        let array_obj = jni::objects::JObject::from(array);

        env.call_method(
            &activity_obj,
            "requestPermissions",
            "([Ljava/lang/String;I)V",
            &[
                jni::objects::JValue::Object(&array_obj),
                jni::objects::JValue::Int(19019),
            ],
        )?;

        Ok(true)
    });

    match result {
        Ok(value) => value,
        Err(_) => {
            let _ = env.exception_clear();
            false
        }
    }
}

extern "C" fn rodin_photo_frame_callback(_frame_time_nanos: i64, _data: *mut core::ffi::c_void) {
    RODIN_PHOTO_REQUEST_SCHEDULED.store(false, std::sync::atomic::Ordering::Release);

    if !RODIN_PHOTO_REQUEST_PENDING.swap(false, std::sync::atomic::Ordering::AcqRel) {
        return;
    }

    let activity =
        RODIN_PHOTO_ACTIVITY.load(std::sync::atomic::Ordering::Acquire) as *mut ANativeActivity;

    if !activity.is_null() {
        let _ = rodin_photo_request_on_main(activity);
    }
}

fn rodin_photo_schedule_request() -> bool {
    let choreographer = RODIN_PHOTO_CHOREOGRAPHER.load(std::sync::atomic::Ordering::Acquire)
        as *mut core::ffi::c_void;

    if choreographer.is_null() {
        return false;
    }

    RODIN_PHOTO_REQUEST_PENDING.store(true, std::sync::atomic::Ordering::Release);

    if RODIN_PHOTO_REQUEST_SCHEDULED
        .compare_exchange(
            false,
            true,
            std::sync::atomic::Ordering::AcqRel,
            std::sync::atomic::Ordering::Acquire,
        )
        .is_err()
    {
        return true;
    }

    unsafe {
        AChoreographer_postFrameCallback64(
            choreographer as *mut AChoreographer,
            rodin_photo_frame_callback,
            core::ptr::null_mut(),
        );
    }

    true
}

fn rodin_photo_init(activity: *mut ANativeActivity) {
    if activity.is_null() {
        return;
    }

    RODIN_PHOTO_ACTIVITY.store(activity as usize, std::sync::atomic::Ordering::Release);

    let choreographer = unsafe { AChoreographer_getInstance() };

    RODIN_PHOTO_CHOREOGRAPHER.store(choreographer as usize, std::sync::atomic::Ordering::Release);

    rodin_photo_refresh_permission(activity);
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_photo_permission_state() -> i32 {
    RODIN_PHOTO_PERMISSION_STATE.load(std::sync::atomic::Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_request_photo_permission() -> i32 {
    if rodin_photo_schedule_request() { 1 } else { 0 }
}
// Dart only posts a semantic integer. JNI work is deferred to the
// NativeActivity main AChoreographer and never runs on Flutter's UI thread.
static RODIN_HAPTIC_ACTIVITY: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);
static RODIN_HAPTIC_CHOREOGRAPHER: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);
static RODIN_HAPTIC_PENDING: std::sync::atomic::AtomicI32 = std::sync::atomic::AtomicI32::new(0);
static RODIN_HAPTIC_SCHEDULED: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

#[link(name = "android")]
unsafe extern "C" {
    #[link_name = "AChoreographer_getInstance"]
    fn rodin_haptic_choreographer_get_instance() -> *mut AChoreographer;

    #[link_name = "AChoreographer_postFrameCallback64"]
    fn rodin_haptic_post_frame_callback64(
        choreographer: *mut AChoreographer,
        callback: unsafe extern "C" fn(i64, *mut c_void),
        data: *mut c_void,
    );
}

fn rodin_haptic_constant(kind: i32, sdk: i32) -> i32 {
    match kind {
        1 => 1, // VIRTUAL_KEY
        2 => 6, // CONTEXT_CLICK
        3 => {
            if sdk >= 34 {
                21
            } else {
                6
            }
        } // TOGGLE_ON
        4 => {
            if sdk >= 34 {
                22
            } else {
                6
            }
        } // TOGGLE_OFF
        5 => {
            if sdk >= 34 {
                26
            } else {
                4
            }
        } // SEGMENT_TICK
        6 => {
            if sdk >= 34 {
                27
            } else {
                4
            }
        } // SEGMENT_FREQUENT_TICK
        7 => {
            if sdk >= 30 {
                16
            } else {
                1
            }
        } // CONFIRM
        8 => {
            if sdk >= 30 {
                17
            } else {
                6
            }
        } // REJECT
        9 => {
            if sdk >= 30 {
                13
            } else {
                8
            }
        } // End gesture.
        _ => 1,
    }
}

fn rodin_haptic_perform_on_main(kind: i32) -> bool {
    let activity_ptr =
        RODIN_HAPTIC_ACTIVITY.load(std::sync::atomic::Ordering::Acquire) as *mut ANativeActivity;

    if activity_ptr.is_null() {
        return false;
    }

    let (vm_raw, activity_raw, sdk) = unsafe {
        (
            (*activity_ptr).vm as *mut jni::sys::JavaVM,
            (*activity_ptr).clazz as jni::sys::jobject,
            (*activity_ptr).sdk_version,
        )
    };

    if vm_raw.is_null() || activity_raw.is_null() {
        return false;
    }

    let vm = match unsafe { jni::JavaVM::from_raw(vm_raw) } {
        Ok(vm) => vm,
        Err(_) => return false,
    };

    let mut env = match vm.get_env() {
        Ok(env) => env,
        Err(_) => return false,
    };

    let constant = rodin_haptic_constant(kind, sdk);

    let result: jni::errors::Result<bool> = env.with_local_frame(8, |env| {
        let activity = unsafe { jni::objects::JObject::from_raw(activity_raw) };

        let window = env
            .call_method(&activity, "getWindow", "()Landroid/view/Window;", &[])?
            .l()?;

        let decor = env
            .call_method(&window, "getDecorView", "()Landroid/view/View;", &[])?
            .l()?;

        env.call_method(
            &decor,
            "performHapticFeedback",
            "(I)Z",
            &[jni::objects::JValue::Int(constant)],
        )?
        .z()
    });

    match result {
        Ok(accepted) => accepted,
        Err(_) => {
            let _ = env.exception_clear();
            false
        }
    }
}

extern "C" fn rodin_haptic_frame_callback(_frame_time_nanos: i64, _data: *mut core::ffi::c_void) {
    RODIN_HAPTIC_SCHEDULED.store(false, std::sync::atomic::Ordering::Release);

    let kind = RODIN_HAPTIC_PENDING.swap(0, std::sync::atomic::Ordering::AcqRel);

    if kind != 0 {
        let _ = rodin_haptic_perform_on_main(kind);
    }

    if RODIN_HAPTIC_PENDING.load(std::sync::atomic::Ordering::Acquire) != 0 {
        let _ = rodin_host_haptic_schedule();
    }
}

fn rodin_host_haptic_schedule() -> bool {
    let choreographer = RODIN_HAPTIC_CHOREOGRAPHER.load(std::sync::atomic::Ordering::Acquire)
        as *mut core::ffi::c_void;

    if choreographer.is_null() {
        return false;
    }

    if RODIN_HAPTIC_SCHEDULED
        .compare_exchange(
            false,
            true,
            std::sync::atomic::Ordering::AcqRel,
            std::sync::atomic::Ordering::Acquire,
        )
        .is_err()
    {
        return true;
    }

    unsafe {
        rodin_haptic_post_frame_callback64(
            choreographer as *mut AChoreographer,
            rodin_haptic_frame_callback,
            core::ptr::null_mut(),
        );
    }

    true
}

fn rodin_haptic_init(activity: *mut ANativeActivity) {
    if activity.is_null() {
        return;
    }

    RODIN_HAPTIC_ACTIVITY.store(activity as usize, std::sync::atomic::Ordering::Release);

    let choreographer = unsafe { rodin_haptic_choreographer_get_instance() };
    RODIN_HAPTIC_CHOREOGRAPHER.store(choreographer as usize, std::sync::atomic::Ordering::Release);
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_haptic(kind: i32) -> i32 {
    if !(1..=9).contains(&kind) {
        return 0;
    }

    if RODIN_HAPTIC_ACTIVITY.load(std::sync::atomic::Ordering::Acquire) == 0 {
        return 0;
    }

    // Coalesce bursts to one semantic feedback request per Android frame.
    RODIN_HAPTIC_PENDING.store(kind, std::sync::atomic::Ordering::Release);
    if rodin_host_haptic_schedule() { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_haptic_ready() -> i32 {
    if RODIN_HAPTIC_ACTIVITY.load(std::sync::atomic::Ordering::Acquire) != 0
        && RODIN_HAPTIC_CHOREOGRAPHER.load(std::sync::atomic::Ordering::Acquire) != 0
    {
        1
    } else {
        0
    }
}

pub fn rodin_host_open_url_jni(code: i32) -> bool {
    let url = match code {
        0 => "https://github.com/NEESCHAL-3",
        1 => "https://t.me/PocoX7ProNepalChat",
        _ => return false,
    };

    let activity_ptr =
        RODIN_HAPTIC_ACTIVITY.load(std::sync::atomic::Ordering::Acquire) as *mut ANativeActivity;

    if activity_ptr.is_null() {
        eprintln!("RODIN_OPEN_URL activity_ptr is null");
        return false;
    }

    let (vm_raw, activity_raw) = unsafe {
        (
            (*activity_ptr).vm as *mut jni::sys::JavaVM,
            (*activity_ptr).clazz as jni::sys::jobject,
        )
    };

    if vm_raw.is_null() || activity_raw.is_null() {
        eprintln!("RODIN_OPEN_URL vm or activity is null");
        return false;
    }

    let vm = match unsafe { jni::JavaVM::from_raw(vm_raw) } {
        Ok(vm) => vm,
        Err(e) => {
            eprintln!("RODIN_OPEN_URL JavaVM::from_raw error {e:?}");
            return false;
        }
    };

    let mut env = match vm.attach_current_thread() {
        Ok(env) => env,
        Err(e) => {
            eprintln!("RODIN_OPEN_URL attach_current_thread error {e:?}");
            return false;
        }
    };

    let result: jni::errors::Result<bool> = env.with_local_frame(16, |env| {
        let activity = unsafe { jni::objects::JObject::from_raw(activity_raw) };
        let url_jstring = env.new_string(url)?;

        let uri_class = env.find_class("android/net/Uri")?;
        let uri = env
            .call_static_method(
                &uri_class,
                "parse",
                "(Ljava/lang/String;)Landroid/net/Uri;",
                &[(&url_jstring).into()],
            )?
            .l()?;

        let action_view = env.new_string("android.intent.action.VIEW")?;
        let intent_class = env.find_class("android/content/Intent")?;
        let intent = env.new_object(
            &intent_class,
            "(Ljava/lang/String;Landroid/net/Uri;)V",
            &[(&action_view).into(), (&uri).into()],
        )?;

        let _ = env.call_method(
            &intent,
            "addFlags",
            "(I)Landroid/content/Intent;",
            &[jni::objects::JValue::Int(0x10000000)],
        );

        env.call_method(
            &activity,
            "startActivity",
            "(Landroid/content/Intent;)V",
            &[(&intent).into()],
        )?;

        Ok(true)
    });

    match result {
        Ok(true) => {
            eprintln!("RODIN_OPEN_URL launched {url}");
            true
        }
        Ok(false) => false,
        Err(e) => {
            eprintln!("RODIN_OPEN_URL JNI error {e:?}");
            false
        }
    }
}
static RODIN_BACK_INTERCEPT: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);
static RODIN_BACK_PENDING: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

#[link(name = "android")]
unsafe extern "C" {
    #[link_name = "AInputEvent_getType"]
    fn rodin_input_event_get_type(event: *const AInputEvent) -> i32;

    #[link_name = "AKeyEvent_getAction"]
    fn rodin_key_event_get_action(event: *const AInputEvent) -> i32;

    #[link_name = "AKeyEvent_getKeyCode"]
    fn rodin_key_event_get_key_code(event: *const AInputEvent) -> i32;
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_set_back_intercept(enabled: i32) -> i32 {
    let value = enabled != 0;
    RODIN_BACK_INTERCEPT.store(value, std::sync::atomic::Ordering::Release);

    if !value {
        RODIN_BACK_PENDING.store(false, std::sync::atomic::Ordering::Release);
    }

    1
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_consume_back_request() -> i32 {
    if RODIN_BACK_PENDING.swap(false, std::sync::atomic::Ordering::AcqRel) {
        1
    } else {
        0
    }
}

fn rodin_back_finish_handled(event: *const core::ffi::c_void, original_handled: i32) -> i32 {
    if event.is_null() || !RODIN_BACK_INTERCEPT.load(std::sync::atomic::Ordering::Acquire) {
        return original_handled;
    }

    const AINPUT_EVENT_TYPE_KEY: i32 = 1;
    const AKEYCODE_BACK: i32 = 4;
    const AKEY_EVENT_ACTION_UP: i32 = 1;

    let event_type = unsafe { rodin_input_event_get_type(event as *const AInputEvent) };
    if event_type != AINPUT_EVENT_TYPE_KEY {
        return original_handled;
    }

    let key_code = unsafe { rodin_key_event_get_key_code(event as *const AInputEvent) };
    if key_code != AKEYCODE_BACK {
        return original_handled;
    }

    let action = unsafe { rodin_key_event_get_action(event as *const AInputEvent) };
    if action == AKEY_EVENT_ACTION_UP {
        RODIN_BACK_PENDING.store(true, std::sync::atomic::Ordering::Release);
    }

    // Consume DOWN + UP only while Rodin has an internal page to go back to.
    1
}

include!("flutter_layout.rs");

const ANDROID_LOG_INFO: c_int = 4;
const WINDOW_FORMAT_RGBA_8888: c_int = 1;
const AASSET_MODE_STREAMING: c_int = 2;
const FLUTTER_ENGINE_VERSION: usize = 1;
const FLUTTER_RENDERER_OPENGL: i32 = 0;

const EGL_FALSE: c_int = 0;
const EGL_NONE: c_int = 0x3038;
const EGL_SURFACE_TYPE: c_int = 0x3033;
const EGL_WINDOW_BIT: c_int = 0x0004;
const EGL_PBUFFER_BIT: c_int = 0x0001;
const EGL_RENDERABLE_TYPE: c_int = 0x3040;
const EGL_OPENGL_ES3_BIT: c_int = 0x0040;
const EGL_RED_SIZE: c_int = 0x3024;
const EGL_GREEN_SIZE: c_int = 0x3023;
const EGL_BLUE_SIZE: c_int = 0x3022;
const EGL_ALPHA_SIZE: c_int = 0x3021;
const EGL_CONTEXT_CLIENT_VERSION: c_int = 0x3098;
const EGL_NATIVE_VISUAL_ID: c_int = 0x302E;
const EGL_WIDTH: c_int = 0x3057;
const EGL_HEIGHT: c_int = 0x3056;
const EGL_OPENGL_ES_API: u32 = 0x30A0;
const RTLD_NOW: c_int = 2;

const ALOOPER_PREPARE_ALLOW_NON_CALLBACKS: c_int = 1;
const INPUT_LOOPER_IDENT: c_int = 1;

const AINPUT_EVENT_TYPE_KEY: i32 = 1;
const AINPUT_EVENT_TYPE_MOTION: i32 = 2;

const AMOTION_EVENT_ACTION_MASK: i32 = 0xff;
const AMOTION_EVENT_ACTION_POINTER_INDEX_MASK: i32 = 0xff00;
const AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT: i32 = 8;
const AMOTION_EVENT_ACTION_DOWN: i32 = 0;
const AMOTION_EVENT_ACTION_UP: i32 = 1;
const AMOTION_EVENT_ACTION_MOVE: i32 = 2;
const AMOTION_EVENT_ACTION_CANCEL: i32 = 3;
const AMOTION_EVENT_ACTION_POINTER_DOWN: i32 = 5;
const AMOTION_EVENT_ACTION_POINTER_UP: i32 = 6;

const FLUTTER_POINTER_CANCEL: i32 = 0;
const FLUTTER_POINTER_UP: i32 = 1;
const FLUTTER_POINTER_DOWN: i32 = 2;
const FLUTTER_POINTER_MOVE: i32 = 3;
const FLUTTER_POINTER_ADD: i32 = 4;
const FLUTTER_POINTER_REMOVE: i32 = 5;
const FLUTTER_POINTER_SIGNAL_NONE: i32 = 0;
const FLUTTER_POINTER_DEVICE_TOUCH: i32 = 2;

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
    on_input_queue_created: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut AInputQueue)>,
    on_input_queue_destroyed: Option<unsafe extern "C" fn(*mut ANativeActivity, *mut AInputQueue)>,
    on_content_rect_changed: Option<unsafe extern "C" fn(*mut ANativeActivity, *const ARect)>,
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
pub struct AInputEvent {
    _private: [u8; 0],
}

#[repr(C)]
pub struct ALooper {
    _private: [u8; 0],
}

#[repr(C)]
pub struct AChoreographer {
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

struct InputWorker {
    queue: usize,
    stop: Arc<AtomicBool>,
    looper: Arc<AtomicUsize>,
    thread: JoinHandle<()>,
}

#[derive(Default)]
struct EglState {
    display: usize,
    config: usize,
    surface: usize,
    context: usize,
    resource_surface: usize,
    resource_context: usize,
    retired_surfaces: Vec<usize>,
    surface_generation: u64,
    bound_generation: u64,
    presented_generation: u64,
}

struct VsyncShared {
    engine: AtomicUsize,
    choreographer: AtomicUsize,
    period_nanos: AtomicI64,
    alive: AtomicBool,
    first_logged: AtomicBool,
}

impl VsyncShared {
    fn new() -> Self {
        Self {
            engine: AtomicUsize::new(0),
            choreographer: AtomicUsize::new(0),
            period_nanos: AtomicI64::new(8_333_333),
            alive: AtomicBool::new(true),
            first_logged: AtomicBool::new(false),
        }
    }
}

struct HostState {
    window: Mutex<usize>,
    engine: Mutex<usize>,
    app_handle: Mutex<usize>,
    input_worker: Mutex<Option<InputWorker>>,
    egl: Mutex<EglState>,
    vsync: Arc<VsyncShared>,
    first_frame_logged: AtomicBool,
    first_input_logged: AtomicBool,
}

impl HostState {
    fn new() -> Self {
        Self {
            window: Mutex::new(0),
            engine: Mutex::new(0),
            app_handle: Mutex::new(0),
            input_worker: Mutex::new(None),
            egl: Mutex::new(EglState::default()),
            vsync: Arc::new(VsyncShared::new()),
            first_frame_logged: AtomicBool::new(false),
            first_input_logged: AtomicBool::new(false),
        }
    }
}

#[link(name = "log")]
unsafe extern "C" {
    fn __android_log_write(prio: c_int, tag: *const c_char, text: *const c_char) -> c_int;
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

    #[allow(dead_code)]
    fn ANativeWindow_lock(
        window: *mut ANativeWindow,
        out_buffer: *mut ANativeWindowBuffer,
        in_out_dirty_bounds: *mut ARect,
    ) -> i32;

    #[allow(dead_code)]
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
    fn AConfiguration_fromAssetManager(config: *mut AConfiguration, manager: *mut AAssetManager);
    fn AConfiguration_getDensity(config: *mut AConfiguration) -> i32;

    fn ALooper_prepare(opts: c_int) -> *mut ALooper;
    fn ALooper_pollOnce(
        timeout_millis: c_int,
        out_fd: *mut c_int,
        out_events: *mut c_int,
        out_data: *mut *mut c_void,
    ) -> c_int;
    fn ALooper_wake(looper: *mut ALooper);

    fn AInputQueue_attachLooper(
        queue: *mut AInputQueue,
        looper: *mut ALooper,
        ident: c_int,
        callback: Option<unsafe extern "C" fn(c_int, c_int, *mut c_void) -> c_int>,
        data: *mut c_void,
    );
    fn AInputQueue_detachLooper(queue: *mut AInputQueue);
    fn AInputQueue_getEvent(queue: *mut AInputQueue, out_event: *mut *mut AInputEvent) -> i32;
    fn AInputQueue_preDispatchEvent(queue: *mut AInputQueue, event: *mut AInputEvent) -> i32;
    fn AInputQueue_finishEvent(queue: *mut AInputQueue, event: *mut AInputEvent, handled: c_int);

    fn AInputEvent_getType(event: *const AInputEvent) -> i32;
    fn AMotionEvent_getAction(event: *const AInputEvent) -> i32;
    fn AMotionEvent_getEventTime(event: *const AInputEvent) -> i64;
    fn AMotionEvent_getPointerCount(event: *const AInputEvent) -> usize;
    fn AMotionEvent_getPointerId(event: *const AInputEvent, pointer_index: usize) -> i32;
    fn AMotionEvent_getX(event: *const AInputEvent, pointer_index: usize) -> f32;
    fn AMotionEvent_getY(event: *const AInputEvent, pointer_index: usize) -> f32;
    fn AMotionEvent_getPressure(event: *const AInputEvent, pointer_index: usize) -> f32;

    fn AChoreographer_getInstance() -> *mut AChoreographer;
    fn AChoreographer_postFrameCallback64(
        choreographer: *mut AChoreographer,
        callback: unsafe extern "C" fn(i64, *mut c_void),
        data: *mut c_void,
    );
    fn AChoreographer_registerRefreshRateCallback(
        choreographer: *mut AChoreographer,
        callback: unsafe extern "C" fn(i64, *mut c_void),
        data: *mut c_void,
    );
    fn AChoreographer_unregisterRefreshRateCallback(
        choreographer: *mut AChoreographer,
        callback: unsafe extern "C" fn(i64, *mut c_void),
        data: *mut c_void,
    );
}

#[link(name = "EGL")]
unsafe extern "C" {
    fn eglGetDisplay(native_display: *mut c_void) -> *mut c_void;
    fn eglInitialize(display: *mut c_void, major: *mut c_int, minor: *mut c_int) -> c_int;
    fn eglTerminate(display: *mut c_void) -> c_int;
    fn eglBindAPI(api: u32) -> c_int;
    fn eglChooseConfig(
        display: *mut c_void,
        attribs: *const c_int,
        configs: *mut *mut c_void,
        config_size: c_int,
        num_config: *mut c_int,
    ) -> c_int;
    fn eglGetConfigAttrib(
        display: *mut c_void,
        config: *mut c_void,
        attribute: c_int,
        value: *mut c_int,
    ) -> c_int;
    fn eglCreateWindowSurface(
        display: *mut c_void,
        config: *mut c_void,
        native_window: *mut c_void,
        attribs: *const c_int,
    ) -> *mut c_void;
    fn eglCreatePbufferSurface(
        display: *mut c_void,
        config: *mut c_void,
        attribs: *const c_int,
    ) -> *mut c_void;
    fn eglDestroySurface(display: *mut c_void, surface: *mut c_void) -> c_int;
    fn eglCreateContext(
        display: *mut c_void,
        config: *mut c_void,
        share_context: *mut c_void,
        attribs: *const c_int,
    ) -> *mut c_void;
    fn eglDestroyContext(display: *mut c_void, context: *mut c_void) -> c_int;
    fn eglMakeCurrent(
        display: *mut c_void,
        draw: *mut c_void,
        read: *mut c_void,
        context: *mut c_void,
    ) -> c_int;
    fn eglSwapBuffers(display: *mut c_void, surface: *mut c_void) -> c_int;
    fn eglSwapInterval(display: *mut c_void, interval: c_int) -> c_int;
    fn eglGetError() -> c_int;
    fn eglGetProcAddress(procname: *const c_char) -> *const c_void;
}

#[link(name = "GLESv3")]
unsafe extern "C" {
    fn glClearColor(red: f32, green: f32, blue: f32, alpha: f32);
    fn glClear(mask: u32);
    fn glViewport(x: i32, y: i32, width: i32, height: i32);
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

    fn FlutterEngineSendWindowMetricsEvent(engine: *mut c_void, event: *const c_void) -> c_int;

    fn FlutterEngineSendPointerEvent(
        engine: *mut c_void,
        events: *const c_void,
        events_count: usize,
    ) -> c_int;

    fn FlutterEngineScheduleFrame(engine: *mut c_void) -> c_int;

    fn FlutterEngineOnVsync(
        engine: *mut c_void,
        baton: isize,
        frame_start_time_nanos: u64,
        frame_target_time_nanos: u64,
    ) -> c_int;

    fn FlutterEngineNotifyLowMemoryWarning(engine: *mut c_void) -> c_int;

    fn FlutterEngineSendPlatformMessage(engine: *mut c_void, message: *const c_void) -> c_int;

    fn FlutterEngineRunsAOTCompiledDartCode() -> bool;
}

fn log_str(message: &str) {
    static TAG: &[u8] = b"RodinEssential\0";

    let clean = message.replace('\0', " ");
    if let Ok(text) = CString::new(clean) {
        unsafe {
            __android_log_write(ANDROID_LOG_INFO, TAG.as_ptr().cast(), text.as_ptr());
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
            ptr::write_unaligned(buffer.as_mut_ptr().add(offset).cast::<usize>(), value);
        }
    }
}

fn put_i32(buffer: &mut [u8], offset: usize, value: i32) {
    if offset + core::mem::size_of::<i32>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(buffer.as_mut_ptr().add(offset).cast::<i32>(), value);
        }
    }
}

fn put_u64(buffer: &mut [u8], offset: usize, value: u64) {
    if offset + core::mem::size_of::<u64>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(buffer.as_mut_ptr().add(offset).cast::<u64>(), value);
        }
    }
}

fn put_i64(buffer: &mut [u8], offset: usize, value: i64) {
    if offset + core::mem::size_of::<i64>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(buffer.as_mut_ptr().add(offset).cast::<i64>(), value);
        }
    }
}

fn put_f64(buffer: &mut [u8], offset: usize, value: f64) {
    if offset + core::mem::size_of::<f64>() <= buffer.len() {
        unsafe {
            ptr::write_unaligned(buffer.as_mut_ptr().add(offset).cast::<f64>(), value);
        }
    }
}

fn put_bool(buffer: &mut [u8], offset: usize, value: bool) {
    if offset < buffer.len() {
        buffer[offset] = u8::from(value);
    }
}

fn read_asset(manager: *mut AAssetManager, name: &str) -> Result<Vec<u8>, String> {
    let c_name = CString::new(name).map_err(|_| format!("invalid asset name: {name}"))?;

    let asset = unsafe { AAssetManager_open(manager, c_name.as_ptr(), AASSET_MODE_STREAMING) };

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

fn asset_length(manager: *mut AAssetManager, name: &str) -> Result<u64, String> {
    let c_name = CString::new(name).map_err(|_| format!("invalid asset name: {name}"))?;
    let asset = unsafe { AAssetManager_open(manager, c_name.as_ptr(), AASSET_MODE_STREAMING) };

    if asset.is_null() {
        return Err(format!("asset not found: {name}"));
    }

    let length = unsafe { AAsset_getLength64(asset) };
    unsafe { AAsset_close(asset) };

    if length < 0 {
        Err(format!("invalid asset length: {name}"))
    } else {
        Ok(length as u64)
    }
}

fn cached_file_matches_asset(manager: *mut AAssetManager, name: &str, path: &Path) -> bool {
    let Ok(expected_length) = asset_length(manager, name) else {
        return false;
    };
    let Ok(metadata) = std::fs::metadata(path) else {
        return false;
    };

    metadata.is_file() && metadata.len() == expected_length
}

fn write_file(path: &Path, data: &[u8]) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        create_dir_all(parent).map_err(|e| format!("mkdir {}: {e}", parent.display()))?;
    }

    let mut file = File::create(path).map_err(|e| format!("create {}: {e}", path.display()))?;

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
    let icu_path = base.join("icudtl.dat");
    let stamp_path = base.join(".assets_stamp");

    create_dir_all(&assets_dir).map_err(|e| format!("mkdir {}: {e}", assets_dir.display()))?;
    create_dir_all(&cache_dir).map_err(|e| format!("mkdir {}: {e}", cache_dir.display()))?;

    let index = String::from_utf8(read_asset(manager, "flutter_assets.index")?)
        .map_err(|e| format!("flutter_assets.index UTF-8: {e}"))?;
    let packaged_stamp = read_asset(manager, "rodin_runtime.stamp")?;
    let required_assets: Vec<&str> = index
        .lines()
        .map(str::trim)
        .filter(|relative| !relative.is_empty())
        .collect();

    let stamp_matches = match std::fs::read(&stamp_path) {
        Ok(existing_stamp) => existing_stamp == packaged_stamp,
        Err(_) => false,
    };
    let files_complete = stamp_matches
        && cached_file_matches_asset(manager, "icudtl.dat", &icu_path)
        && required_assets.iter().all(|relative| {
            let asset_name = format!("flutter_assets/{relative}");
            cached_file_matches_asset(manager, &asset_name, &assets_dir.join(relative))
        });
    let needs_extract = !files_complete;

    if needs_extract {
        let mut copied = 0usize;

        for relative in &required_assets {
            let asset_name = format!("flutter_assets/{relative}");
            let data = read_asset(manager, &asset_name)?;
            write_file(&assets_dir.join(relative), &data)?;
            copied += 1;
        }

        let icu = read_asset(manager, "icudtl.dat")?;
        write_file(&icu_path, &icu)?;
        write_file(&stamp_path, &packaged_stamp)?;

        log_str(&format!(
            "runtime assets extracted: files={copied} icu={} bytes",
            icu.len()
        ));
    } else {
        log_str(&format!(
            "runtime assets cache hit: files={} icu={}",
            required_assets.len(),
            std::fs::metadata(&icu_path).map_or(0, |metadata| metadata.len())
        ));
    }

    let assets_c = CString::new(assets_dir.to_string_lossy().as_bytes())
        .map_err(|_| "assets path contains NUL".to_string())?;
    let icu_c = CString::new(icu_path.to_string_lossy().as_bytes())
        .map_err(|_| "ICU path contains NUL".to_string())?;
    let cache_c = CString::new(cache_dir.to_string_lossy().as_bytes())
        .map_err(|_| "cache path contains NUL".to_string())?;

    Ok((assets_c, icu_c, cache_c))
}

fn input_engine(state: *mut HostState) -> usize {
    if state.is_null() {
        return 0;
    }

    let guard = match unsafe { &*state }.engine.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    *guard
}

unsafe fn send_touch_pointer(
    state: *mut HostState,
    motion_event: *const AInputEvent,
    pointer_index: usize,
    phase: i32,
) -> bool {
    let engine = input_engine(state);

    if engine == 0 || motion_event.is_null() {
        return false;
    }

    let pointer_count = unsafe { AMotionEvent_getPointerCount(motion_event) };
    if pointer_index >= pointer_count {
        return false;
    }

    let timestamp_ns = unsafe { AMotionEvent_getEventTime(motion_event) };
    let timestamp_us = if timestamp_ns > 0 {
        (timestamp_ns as usize) / 1000
    } else {
        0
    };

    let x = unsafe { AMotionEvent_getX(motion_event, pointer_index) } as f64;
    let y = unsafe { AMotionEvent_getY(motion_event, pointer_index) } as f64;
    let device = unsafe { AMotionEvent_getPointerId(motion_event, pointer_index) };
    let pressure = unsafe { AMotionEvent_getPressure(motion_event, pointer_index) } as f64;

    let mut pointer = vec![0u8; FLUTTER_POINTER_EVENT_SIZE];

    put_usize(
        &mut pointer,
        OFF_POINTER_STRUCT_SIZE,
        FLUTTER_POINTER_EVENT_SIZE,
    );
    put_i32(&mut pointer, OFF_POINTER_PHASE, phase);
    put_usize(&mut pointer, OFF_POINTER_TIMESTAMP, timestamp_us);
    put_f64(&mut pointer, OFF_POINTER_X, x);
    put_f64(&mut pointer, OFF_POINTER_Y, y);
    put_i32(&mut pointer, OFF_POINTER_DEVICE, device);
    put_i32(
        &mut pointer,
        OFF_POINTER_SIGNAL_KIND,
        FLUTTER_POINTER_SIGNAL_NONE,
    );
    put_f64(&mut pointer, OFF_POINTER_SCROLL_X, 0.0);
    put_f64(&mut pointer, OFF_POINTER_SCROLL_Y, 0.0);
    put_i32(
        &mut pointer,
        OFF_POINTER_DEVICE_KIND,
        FLUTTER_POINTER_DEVICE_TOUCH,
    );
    put_i64(&mut pointer, OFF_POINTER_BUTTONS, 0);
    put_i64(&mut pointer, OFF_POINTER_VIEW_ID, 0);
    put_f64(&mut pointer, OFF_POINTER_PRESSURE, pressure);
    put_f64(&mut pointer, OFF_POINTER_PRESSURE_MIN, 0.0);
    put_f64(&mut pointer, OFF_POINTER_PRESSURE_MAX, 1.0);

    let result =
        unsafe { FlutterEngineSendPointerEvent(engine as *mut c_void, pointer.as_ptr().cast(), 1) };

    result == 0
}

unsafe fn handle_motion_event(state: *mut HostState, event: *mut AInputEvent) -> bool {
    let action = unsafe { AMotionEvent_getAction(event) };
    let masked = action & AMOTION_EVENT_ACTION_MASK;
    let pointer_count = unsafe { AMotionEvent_getPointerCount(event) };

    if pointer_count == 0 {
        return false;
    }

    let action_index = ((action & AMOTION_EVENT_ACTION_POINTER_INDEX_MASK)
        >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT) as usize;

    match masked {
        AMOTION_EVENT_ACTION_DOWN | AMOTION_EVENT_ACTION_POINTER_DOWN => {
            if action_index >= pointer_count {
                return false;
            }

            let add_ok =
                unsafe { send_touch_pointer(state, event, action_index, FLUTTER_POINTER_ADD) };
            let down_ok =
                unsafe { send_touch_pointer(state, event, action_index, FLUTTER_POINTER_DOWN) };

            if !state.is_null()
                && !unsafe { &*state }
                    .first_input_logged
                    .swap(true, Ordering::AcqRel)
            {
                let x = unsafe { AMotionEvent_getX(event, action_index) };
                let y = unsafe { AMotionEvent_getY(event, action_index) };
                log_str(&format!("INPUT_TOUCH=PASS action=DOWN x={x:.1} y={y:.1}"));
            }

            add_ok && down_ok
        }
        AMOTION_EVENT_ACTION_MOVE => {
            let mut ok = true;

            for index in 0..pointer_count {
                ok &= unsafe { send_touch_pointer(state, event, index, FLUTTER_POINTER_MOVE) };
            }

            ok
        }
        AMOTION_EVENT_ACTION_UP | AMOTION_EVENT_ACTION_POINTER_UP => {
            if action_index >= pointer_count {
                return false;
            }

            let up_ok =
                unsafe { send_touch_pointer(state, event, action_index, FLUTTER_POINTER_UP) };
            let remove_ok =
                unsafe { send_touch_pointer(state, event, action_index, FLUTTER_POINTER_REMOVE) };

            up_ok && remove_ok
        }
        AMOTION_EVENT_ACTION_CANCEL => {
            let mut ok = true;

            for index in 0..pointer_count {
                ok &= unsafe { send_touch_pointer(state, event, index, FLUTTER_POINTER_CANCEL) };
                ok &= unsafe { send_touch_pointer(state, event, index, FLUTTER_POINTER_REMOVE) };
            }

            ok
        }
        _ => false,
    }
}

fn input_worker_main(
    queue_value: usize,
    state_value: usize,
    stop: Arc<AtomicBool>,
    looper_slot: Arc<AtomicUsize>,
    ready: mpsc::Sender<bool>,
) {
    let queue = queue_value as *mut AInputQueue;
    let state = state_value as *mut HostState;

    if queue.is_null() || state.is_null() {
        let _ = ready.send(false);
        return;
    }

    unsafe {
        let looper = ALooper_prepare(ALOOPER_PREPARE_ALLOW_NON_CALLBACKS);

        if looper.is_null() {
            log_str("INPUT_QUEUE=FAIL looper=null");
            let _ = ready.send(false);
            return;
        }

        AInputQueue_attachLooper(queue, looper, INPUT_LOOPER_IDENT, None, ptr::null_mut());

        looper_slot.store(looper as usize, Ordering::Release);
        log_str("INPUT_QUEUE=READY");
        let _ = ready.send(true);

        while !stop.load(Ordering::Acquire) {
            let ident = ALooper_pollOnce(250, ptr::null_mut(), ptr::null_mut(), ptr::null_mut());

            if stop.load(Ordering::Acquire) {
                break;
            }

            if ident != INPUT_LOOPER_IDENT {
                continue;
            }

            loop {
                let mut event: *mut AInputEvent = ptr::null_mut();

                if AInputQueue_getEvent(queue, &mut event) < 0 {
                    break;
                }

                if event.is_null() {
                    break;
                }

                let event_type = AInputEvent_getType(event);

                if event_type == AINPUT_EVENT_TYPE_KEY
                    && AInputQueue_preDispatchEvent(queue, event) != 0
                {
                    continue;
                }

                let handled = if event_type == AINPUT_EVENT_TYPE_MOTION {
                    if handle_motion_event(state, event) {
                        1
                    } else {
                        0
                    }
                } else {
                    0
                };

                AInputQueue_finishEvent(
                    queue,
                    event,
                    rodin_back_finish_handled((event) as *const core::ffi::c_void, handled),
                );
            }
        }

        AInputQueue_detachLooper(queue);
        looper_slot.store(0, Ordering::Release);
        log_str("INPUT_QUEUE=STOPPED");
    }
}

fn stop_input_worker(state: *mut HostState) {
    if state.is_null() {
        return;
    }

    let worker = {
        let mut guard = match unsafe { &*state }.input_worker.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        };
        guard.take()
    };

    let Some(worker) = worker else {
        return;
    };

    worker.stop.store(true, Ordering::Release);

    let looper = worker.looper.load(Ordering::Acquire);
    if looper != 0 {
        unsafe {
            ALooper_wake(looper as *mut ALooper);
        }
    }

    match worker.thread.join() {
        Ok(()) => {
            log_str(&format!("input worker joined queue=0x{:x}", worker.queue));
        }
        Err(_) => {
            log_str("input worker join failed");
        }
    }
}

fn start_input_worker(state: *mut HostState, queue: *mut AInputQueue) {
    if state.is_null() || queue.is_null() {
        log_str("INPUT_QUEUE=FAIL null state/queue");
        return;
    }

    stop_input_worker(state);

    let stop = Arc::new(AtomicBool::new(false));
    let looper = Arc::new(AtomicUsize::new(0));
    let (ready_tx, ready_rx) = mpsc::channel();

    let thread_stop = Arc::clone(&stop);
    let thread_looper = Arc::clone(&looper);
    let queue_value = queue as usize;
    let state_value = state as usize;

    let thread = std::thread::spawn(move || {
        input_worker_main(
            queue_value,
            state_value,
            thread_stop,
            thread_looper,
            ready_tx,
        );
    });

    match ready_rx.recv_timeout(Duration::from_secs(1)) {
        Ok(true) => {
            let worker = InputWorker {
                queue: queue_value,
                stop,
                looper,
                thread,
            };

            let mut guard = match unsafe { &*state }.input_worker.lock() {
                Ok(guard) => guard,
                Err(poisoned) => poisoned.into_inner(),
            };
            *guard = Some(worker);
        }
        _ => {
            stop.store(true, Ordering::Release);

            let looper_value = looper.load(Ordering::Acquire);
            if looper_value != 0 {
                unsafe {
                    ALooper_wake(looper_value as *mut ALooper);
                }
            }

            let _ = thread.join();
            log_str("INPUT_QUEUE=FAIL worker-not-ready");
        }
    }
}

unsafe extern "C" fn on_input_queue_created(
    activity: *mut ANativeActivity,
    queue: *mut AInputQueue,
) {
    log_str("native input queue created");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };
    start_input_worker(state, queue);
}

unsafe extern "C" fn on_input_queue_destroyed(
    activity: *mut ANativeActivity,
    _queue: *mut AInputQueue,
) {
    log_str("native input queue destroyed");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };
    stop_input_worker(state);
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

fn pixel_ratio_for_window(width: usize, _height: usize, activity: *mut ANativeActivity) -> f64 {
    // Android already publishes the active logical density through the native
    // configuration, including a `wm density` override. Querying the shell
    // wrapper here would block first-frame setup and is forbidden to a normal
    // application domain on enforcing builds.
    let configured_ratio = pixel_ratio(activity);
    if configured_ratio > 1.0 {
        return configured_ratio;
    }

    if width > 0 {
        return (width as f64) / 375.3846;
    }

    configured_ratio
}

unsafe fn symbol(handle: *mut c_void, name: &'static [u8]) -> Result<*const u8, String> {
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

fn egl_error_hex() -> String {
    unsafe { format!("0x{:04x}", eglGetError()) }
}

unsafe fn init_egl(state: *mut HostState, window: *mut ANativeWindow) -> Result<(), String> {
    if state.is_null() || window.is_null() {
        return Err("init_egl null state/window".to_string());
    }

    let host = unsafe { &*state };
    let mut egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 {
        let display = unsafe { eglGetDisplay(ptr::null_mut()) };
        if display.is_null() {
            return Err(format!("eglGetDisplay failed {}", egl_error_hex()));
        }

        let mut major = 0;
        let mut minor = 0;
        if unsafe { eglInitialize(display, &mut major, &mut minor) } == EGL_FALSE {
            return Err(format!("eglInitialize failed {}", egl_error_hex()));
        }

        if unsafe { eglBindAPI(EGL_OPENGL_ES_API) } == EGL_FALSE {
            unsafe { eglTerminate(display) };
            return Err(format!("eglBindAPI failed {}", egl_error_hex()));
        }

        let config_attribs = [
            EGL_SURFACE_TYPE,
            EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
            EGL_RENDERABLE_TYPE,
            EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE,
            8,
            EGL_GREEN_SIZE,
            8,
            EGL_BLUE_SIZE,
            8,
            EGL_ALPHA_SIZE,
            8,
            EGL_NONE,
        ];

        let mut config: *mut c_void = ptr::null_mut();
        let mut config_count = 0;
        if unsafe {
            eglChooseConfig(
                display,
                config_attribs.as_ptr(),
                &mut config,
                1,
                &mut config_count,
            )
        } == EGL_FALSE
            || config_count < 1
            || config.is_null()
        {
            unsafe { eglTerminate(display) };
            return Err(format!("eglChooseConfig failed {}", egl_error_hex()));
        }

        let context_attribs = [EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE];
        let context =
            unsafe { eglCreateContext(display, config, ptr::null_mut(), context_attribs.as_ptr()) };
        if context.is_null() {
            unsafe { eglTerminate(display) };
            return Err(format!("eglCreateContext failed {}", egl_error_hex()));
        }

        let resource_context =
            unsafe { eglCreateContext(display, config, context, context_attribs.as_ptr()) };
        if resource_context.is_null() {
            unsafe {
                eglDestroyContext(display, context);
                eglTerminate(display);
            }
            return Err(format!(
                "eglCreateContext(resource) failed {}",
                egl_error_hex()
            ));
        }

        let pbuffer_attribs = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE];
        let resource_surface =
            unsafe { eglCreatePbufferSurface(display, config, pbuffer_attribs.as_ptr()) };
        if resource_surface.is_null() {
            unsafe {
                eglDestroyContext(display, resource_context);
                eglDestroyContext(display, context);
                eglTerminate(display);
            }
            return Err(format!(
                "eglCreatePbufferSurface failed {}",
                egl_error_hex()
            ));
        }

        egl.display = display as usize;
        egl.config = config as usize;
        egl.context = context as usize;
        egl.resource_context = resource_context as usize;
        egl.resource_surface = resource_surface as usize;

        log_str(&format!("EGL_CONTEXTS=PASS version={major}.{minor}"));
    }

    if egl.surface != 0 {
        return Ok(());
    }

    let display = egl.display as *mut c_void;
    let config = egl.config as *mut c_void;

    let mut visual_id = 0;
    if unsafe { eglGetConfigAttrib(display, config, EGL_NATIVE_VISUAL_ID, &mut visual_id) }
        != EGL_FALSE
        && visual_id != 0
    {
        unsafe {
            ANativeWindow_setBuffersGeometry(window, 0, 0, visual_id);
        }
    }

    let surface_attribs = [EGL_NONE];
    let surface =
        unsafe { eglCreateWindowSurface(display, config, window.cast(), surface_attribs.as_ptr()) };

    if surface.is_null() {
        return Err(format!("eglCreateWindowSurface failed {}", egl_error_hex()));
    }

    // The onscreen context belongs to Flutter's raster thread after startup.
    // Never bind it here on the NativeActivity/platform thread. Rebinding is
    // deferred to the embedder make_current callback on the raster thread.
    egl.surface = surface as usize;
    egl.surface_generation = egl.surface_generation.wrapping_add(1);
    if egl.surface_generation == 0 {
        egl.surface_generation = 1;
    }
    let generation = egl.surface_generation;

    log_str(&format!(
        "EGL_INIT=PASS visual_id={visual_id} renderer=OpenGL_ES3 binding=deferred_raster generation={generation}"
    ));
    log_str(&format!("EGL_SURFACE_READY=PASS generation={generation}"));

    Ok(())
}

unsafe fn retire_egl_surface(state: *mut HostState) {
    if state.is_null() {
        return;
    }

    let host = unsafe { &*state };
    let mut egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.surface != 0 {
        let retired = egl.surface;
        egl.surface = 0;
        egl.retired_surfaces.push(retired);
        log_str(&format!(
            "EGL_WINDOW_SURFACE=RETIRED generation={} pending={} ",
            egl.surface_generation,
            egl.retired_surfaces.len(),
        ));
    }
}

unsafe fn present_launch_background(state: *mut HostState, window: *mut ANativeWindow) {
    const GL_COLOR_BUFFER_BIT: u32 = 0x0000_4000;

    if state.is_null() || window.is_null() {
        return;
    }

    let host = unsafe { &*state };
    let egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 || egl.surface == 0 || egl.context == 0 {
        log_str("LAUNCH_BACKGROUND=FAIL stage=egl_not_ready");
        return;
    }

    let display = egl.display as *mut c_void;
    let surface = egl.surface as *mut c_void;
    let context = egl.context as *mut c_void;
    let width = unsafe { ANativeWindow_getWidth(window) };
    let height = unsafe { ANativeWindow_getHeight(window) };

    if width <= 0 || height <= 0 {
        log_str("LAUNCH_BACKGROUND=FAIL stage=invalid_size");
        return;
    }

    if unsafe { eglMakeCurrent(display, surface, surface, context) } == EGL_FALSE {
        log_str(&format!(
            "LAUNCH_BACKGROUND=FAIL stage=make_current error={}",
            egl_error_hex()
        ));
        return;
    }

    unsafe {
        glViewport(0, 0, width, height);
        glClearColor(1.0, 1.0, 1.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
    }

    let presented = unsafe { eglSwapBuffers(display, surface) } != EGL_FALSE;
    let cleared =
        unsafe { eglMakeCurrent(display, ptr::null_mut(), ptr::null_mut(), ptr::null_mut()) }
            != EGL_FALSE;

    if presented && cleared {
        log_str("LAUNCH_BACKGROUND=PASS renderer=EGL color=white");
    } else {
        log_str(&format!(
            "LAUNCH_BACKGROUND=FAIL stage=present presented={presented} cleared={cleared} error={}",
            egl_error_hex()
        ));
    }
}

unsafe fn destroy_egl_all(state: *mut HostState) {
    if state.is_null() {
        return;
    }

    let host = unsafe { &*state };
    let mut egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 {
        return;
    }

    let display = egl.display as *mut c_void;

    unsafe {
        // FlutterEngineShutdown has already completed before this full teardown,
        // so no raster thread can still own the render context here.
        eglMakeCurrent(display, ptr::null_mut(), ptr::null_mut(), ptr::null_mut());

        if egl.surface != 0 {
            eglDestroySurface(display, egl.surface as *mut c_void);
        }
        for surface in egl.retired_surfaces.drain(..) {
            if surface != 0 {
                eglDestroySurface(display, surface as *mut c_void);
            }
        }
        if egl.resource_surface != 0 {
            eglDestroySurface(display, egl.resource_surface as *mut c_void);
        }
        if egl.resource_context != 0 {
            eglDestroyContext(display, egl.resource_context as *mut c_void);
        }
        if egl.context != 0 {
            eglDestroyContext(display, egl.context as *mut c_void);
        }
        eglTerminate(display);
    }

    *egl = EglState::default();
    log_str("EGL_SHUTDOWN=PASS");
}

unsafe extern "C" fn egl_make_current(user_data: *mut c_void) -> bool {
    if user_data.is_null() {
        return false;
    }

    let host = unsafe { &*(user_data.cast::<HostState>()) };
    let mut egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 || egl.context == 0 {
        return false;
    }

    let display = egl.display as *mut c_void;

    if egl.surface == 0 {
        // This callback runs on Flutter's raster thread. If the old onscreen
        // context is still current here, detach it on its owning thread before
        // reclaiming retired window surfaces.
        let cleared = unsafe {
            eglMakeCurrent(display, ptr::null_mut(), ptr::null_mut(), ptr::null_mut()) != EGL_FALSE
        };

        if cleared && !egl.retired_surfaces.is_empty() {
            let retired_count = egl.retired_surfaces.len();
            for surface in egl.retired_surfaces.drain(..) {
                if surface != 0 {
                    unsafe { eglDestroySurface(display, surface as *mut c_void) };
                }
            }
            log_str(&format!("EGL_RASTER_DETACH=PASS retired={retired_count}"));
        }

        return false;
    }

    let surface = egl.surface as *mut c_void;
    let context = egl.context as *mut c_void;

    if unsafe { eglMakeCurrent(display, surface, surface, context) } == EGL_FALSE {
        log_str(&format!(
            "EGL_RASTER_REBIND=FAIL generation={} error={}",
            egl.surface_generation,
            egl_error_hex(),
        ));
        return false;
    }

    unsafe {
        eglSwapInterval(display, 1);
    }

    let retired_count = egl.retired_surfaces.len();
    for retired in egl.retired_surfaces.drain(..) {
        if retired != 0 && retired != surface as usize {
            unsafe { eglDestroySurface(display, retired as *mut c_void) };
        }
    }

    let generation = egl.surface_generation;
    if egl.bound_generation != generation {
        egl.bound_generation = generation;
        log_str(&format!(
            "EGL_RASTER_REBIND=PASS generation={generation} retired={retired_count}"
        ));
    }

    true
}

unsafe extern "C" fn egl_clear_current(user_data: *mut c_void) -> bool {
    if user_data.is_null() {
        return false;
    }

    let host = unsafe { &*(user_data.cast::<HostState>()) };
    let egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 {
        return false;
    }

    unsafe {
        eglMakeCurrent(
            egl.display as *mut c_void,
            ptr::null_mut(),
            ptr::null_mut(),
            ptr::null_mut(),
        ) != EGL_FALSE
    }
}

unsafe extern "C" fn egl_present(user_data: *mut c_void) -> bool {
    if user_data.is_null() {
        return false;
    }

    let host = unsafe { &*(user_data.cast::<HostState>()) };
    let mut egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 || egl.surface == 0 {
        return false;
    }

    let ok = unsafe {
        eglSwapBuffers(egl.display as *mut c_void, egl.surface as *mut c_void) != EGL_FALSE
    };

    if ok {
        let generation = egl.surface_generation;
        if egl.presented_generation != generation {
            egl.presented_generation = generation;
            log_str(&format!("EGL_PRESENT=PASS generation={generation}"));
        }
    }

    if ok && !host.first_frame_logged.swap(true, Ordering::AcqRel) {
        log_str("GPU_FIRST_FRAME=PASS backend=EGL/OpenGL/Skia");
        log_str("FLUTTER_FIRST_FRAME=PASS renderer=Skia/OpenGL");
    }

    if !ok {
        log_str(&format!("eglSwapBuffers failed {}", egl_error_hex()));
    }

    ok
}

unsafe extern "C" fn egl_fbo(_user_data: *mut c_void) -> u32 {
    0
}

unsafe extern "C" fn egl_make_resource_current(user_data: *mut c_void) -> bool {
    if user_data.is_null() {
        return false;
    }

    let host = unsafe { &*(user_data.cast::<HostState>()) };
    let egl = match host.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    if egl.display == 0 || egl.resource_surface == 0 || egl.resource_context == 0 {
        return false;
    }

    unsafe {
        eglMakeCurrent(
            egl.display as *mut c_void,
            egl.resource_surface as *mut c_void,
            egl.resource_surface as *mut c_void,
            egl.resource_context as *mut c_void,
        ) != EGL_FALSE
    }
}

unsafe extern "C" fn egl_proc_resolver(
    _user_data: *mut c_void,
    name: *const c_char,
) -> *const c_void {
    if name.is_null() {
        ptr::null()
    } else {
        unsafe { eglGetProcAddress(name) }
    }
}

struct VsyncRequest {
    shared: Arc<VsyncShared>,
    baton: isize,
}

unsafe extern "C" fn choreographer_frame_callback(frame_time_nanos: i64, data: *mut c_void) {
    if data.is_null() {
        return;
    }

    let request = unsafe { Box::from_raw(data.cast::<VsyncRequest>()) };

    if !request.shared.alive.load(Ordering::Acquire) {
        return;
    }

    let engine = request.shared.engine.load(Ordering::Acquire);
    if engine == 0 {
        return;
    }

    let period = request.shared.period_nanos.load(Ordering::Acquire).max(1);

    let start = frame_time_nanos.max(0) as u64;
    let target = start.saturating_add(period as u64);

    let result =
        unsafe { FlutterEngineOnVsync(engine as *mut c_void, request.baton, start, target) };

    if !request.shared.first_logged.swap(true, Ordering::AcqRel) {
        log_str(&format!(
            "VSYNC_CHOREOGRAPHER=PASS period_ns={period} rc={result}"
        ));
    }
}

unsafe extern "C" fn flutter_vsync_callback(user_data: *mut c_void, baton: isize) {
    if user_data.is_null() {
        return;
    }

    let host = unsafe { &*(user_data.cast::<HostState>()) };
    let shared = host.vsync.clone();

    if !shared.alive.load(Ordering::Acquire) {
        return;
    }

    let choreographer = shared.choreographer.load(Ordering::Acquire);
    if choreographer == 0 {
        log_str("VSYNC_CHOREOGRAPHER=FAIL no instance");
        return;
    }

    let request = Box::new(VsyncRequest { shared, baton });
    let request_ptr = Box::into_raw(request).cast::<c_void>();

    unsafe {
        AChoreographer_postFrameCallback64(
            choreographer as *mut AChoreographer,
            choreographer_frame_callback,
            request_ptr,
        );
    }
}

unsafe extern "C" fn refresh_rate_callback(period_nanos: i64, data: *mut c_void) {
    if data.is_null() || period_nanos <= 0 {
        return;
    }

    let shared = unsafe { &*(data.cast::<VsyncShared>()) };
    shared.period_nanos.store(period_nanos, Ordering::Release);
    log_str(&format!("DISPLAY_VSYNC_PERIOD_NS={period_nanos}"));
}

unsafe fn send_metrics(activity: *mut ANativeActivity, state: *mut HostState) {
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

    let ratio = pixel_ratio_for_window(width, height, activity);

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
        FlutterEngineSendWindowMetricsEvent(engine_value as *mut c_void, metrics.as_ptr().cast())
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

    let (assets_path, icu_path, cache_path) = prepare_runtime_files(activity)?;

    static LIBAPP: &[u8] = b"libapp.so\0";

    let app_handle = unsafe { dlopen(LIBAPP.as_ptr().cast(), RTLD_NOW) };

    if app_handle.is_null() {
        return Err(format!("dlopen(libapp.so) failed: {}", dl_error_string()));
    }

    let vm_data = match unsafe { symbol(app_handle, b"_kDartVmSnapshotData\0") } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let vm_instructions = match unsafe { symbol(app_handle, b"_kDartVmSnapshotInstructions\0") } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let isolate_data = match unsafe { symbol(app_handle, b"_kDartIsolateSnapshotData\0") } {
        Ok(value) => value,
        Err(error) => {
            unsafe { dlclose(app_handle) };
            return Err(error);
        }
    };

    let isolate_instructions =
        match unsafe { symbol(app_handle, b"_kDartIsolateSnapshotInstructions\0") } {
            Ok(value) => value,
            Err(error) => {
                unsafe { dlclose(app_handle) };
                return Err(error);
            }
        };

    let mut renderer = vec![0u8; FLUTTER_RENDERER_CONFIG_SIZE];
    put_i32(&mut renderer, OFF_RENDERER_TYPE, FLUTTER_RENDERER_OPENGL);

    let gl_base = OFF_RENDERER_OPENGL;

    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_STRUCT_SIZE,
        FLUTTER_OPENGL_RENDERER_CONFIG_SIZE,
    );
    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_MAKE_CURRENT,
        egl_make_current as *const () as usize,
    );
    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_CLEAR_CURRENT,
        egl_clear_current as *const () as usize,
    );
    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_PRESENT,
        egl_present as *const () as usize,
    );
    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_FBO,
        egl_fbo as *const () as usize,
    );
    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_MAKE_RESOURCE_CURRENT,
        egl_make_resource_current as *const () as usize,
    );
    put_bool(
        &mut renderer,
        gl_base + OFF_OPENGL_FBO_RESET_AFTER_PRESENT,
        false,
    );
    put_usize(
        &mut renderer,
        gl_base + OFF_OPENGL_GL_PROC_RESOLVER,
        egl_proc_resolver as *const () as usize,
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
    put_usize(&mut project, OFF_PROJECT_VM_INSTRUCTIONS_SIZE, 0);

    put_usize(
        &mut project,
        OFF_PROJECT_ISOLATE_DATA,
        isolate_data as usize,
    );
    put_usize(&mut project, OFF_PROJECT_ISOLATE_DATA_SIZE, 0);

    put_usize(
        &mut project,
        OFF_PROJECT_ISOLATE_INSTRUCTIONS,
        isolate_instructions as usize,
    );
    put_usize(&mut project, OFF_PROJECT_ISOLATE_INSTRUCTIONS_SIZE, 0);

    put_usize(
        &mut project,
        OFF_PROJECT_PERSISTENT_CACHE_PATH,
        cache_path.as_ptr() as usize,
    );

    put_bool(&mut project, OFF_PROJECT_SHUTDOWN_VM, true);

    put_usize(
        &mut project,
        OFF_PROJECT_LOG_CALLBACK,
        flutter_log_callback as *const () as usize,
    );

    static DART_LOG_TAG: &[u8] = b"RodinDart\0";
    put_usize(
        &mut project,
        OFF_PROJECT_LOG_TAG,
        DART_LOG_TAG.as_ptr() as usize,
    );

    put_bool(&mut project, OFF_PROJECT_ENABLE_WIDE_GAMUT, false);

    put_usize(
        &mut project,
        OFF_PROJECT_VSYNC_CALLBACK,
        flutter_vsync_callback as *const () as usize,
    );

    // The production renderer uses the proven EGL/OpenGL/Skia path. Impeller
    // remains disabled until its custom-embedder lifecycle is validated here.
    static EXECUTABLE_NAME: &[u8] = b"rodin_essential\0";
    static ENABLE_IMPELLER: &[u8] = b"--enable-impeller=false\0";

    let command_line_args: [*const c_char; 2] = [
        EXECUTABLE_NAME.as_ptr().cast(),
        ENABLE_IMPELLER.as_ptr().cast(),
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

    log_str("IMPELLER_REQUEST=OFF backend=OpenGL/Skia");

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

    unsafe { &*state }
        .vsync
        .engine
        .store(engine as usize, Ordering::Release);

    log_str("FLUTTER_ENGINE_RUN=PASS renderer=OpenGL");

    unsafe {
        send_metrics(activity, state);
        send_flutter_settings(activity, state);
    }

    let schedule = unsafe { FlutterEngineScheduleFrame(engine) };
    log_str(&format!("FlutterEngineScheduleFrame rc={schedule}"));

    Ok(())
}

fn rodin_android_user_settings(activity: *mut ANativeActivity) -> (f64, bool, i32) {
    let Some((vm, object_raw, _)) = rodin_photo_vm_and_object(activity) else {
        return (1.0, false, 0);
    };

    let mut env = match vm.get_env() {
        Ok(env) => env,
        Err(_) => return (1.0, false, 0),
    };

    let result: jni::errors::Result<(f64, bool, i32)> = env.with_local_frame(16, |env| {
        let activity_obj = unsafe { jni::objects::JObject::from_raw(object_raw) };

        let resources = env
            .call_method(
                &activity_obj,
                "getResources",
                "()Landroid/content/res/Resources;",
                &[],
            )?
            .l()?;

        let configuration = env
            .call_method(
                &resources,
                "getConfiguration",
                "()Landroid/content/res/Configuration;",
                &[],
            )?
            .l()?;

        let font_scale = env.get_field(&configuration, "fontScale", "F")?.f()? as f64;

        let ui_mode = env.get_field(&configuration, "uiMode", "I")?.i()?;

        let date_format = env.find_class("android/text/format/DateFormat")?;

        let use_24_hour = env
            .call_static_method(
                date_format,
                "is24HourFormat",
                "(Landroid/content/Context;)Z",
                &[jni::objects::JValue::Object(&activity_obj)],
            )?
            .z()?;

        Ok((
            if font_scale.is_finite() && font_scale > 0.0 {
                font_scale
            } else {
                1.0
            },
            use_24_hour,
            ui_mode,
        ))
    });

    match result {
        Ok(value) => value,
        Err(_) => {
            let _ = env.exception_clear();
            (1.0, false, 0)
        }
    }
}

unsafe fn send_flutter_settings(activity: *mut ANativeActivity, state: *mut HostState) -> bool {
    if activity.is_null() || state.is_null() {
        return false;
    }

    let engine = input_engine(state);

    if engine == 0 {
        return false;
    }

    static CHANNEL: &[u8] = b"flutter/settings\0";

    let (text_scale, use_24_hour, ui_mode) = rodin_android_user_settings(activity);

    const UI_MODE_NIGHT_MASK: i32 = 0x30;
    const UI_MODE_NIGHT_YES: i32 = 0x20;

    let brightness = if (ui_mode & UI_MODE_NIGHT_MASK) == UI_MODE_NIGHT_YES {
        "dark"
    } else {
        "light"
    };

    let payload = format!(
        "{{\"textScaleFactor\":{text_scale:.4},\
\"alwaysUse24HourFormat\":{},\
\"platformBrightness\":\"{brightness}\"}}",
        if use_24_hour { "true" } else { "false" },
    );

    let bytes = payload.as_bytes();
    let mut message = vec![0u8; FLUTTER_PLATFORM_MESSAGE_SIZE];

    put_usize(
        &mut message,
        OFF_PLATFORM_MESSAGE_STRUCT_SIZE,
        FLUTTER_PLATFORM_MESSAGE_SIZE,
    );
    put_usize(
        &mut message,
        OFF_PLATFORM_MESSAGE_CHANNEL,
        CHANNEL.as_ptr() as usize,
    );
    put_usize(
        &mut message,
        OFF_PLATFORM_MESSAGE_MESSAGE,
        bytes.as_ptr() as usize,
    );
    put_usize(&mut message, OFF_PLATFORM_MESSAGE_MESSAGE_SIZE, bytes.len());
    put_usize(&mut message, OFF_PLATFORM_MESSAGE_RESPONSE_HANDLE, 0);

    let rc =
        unsafe { FlutterEngineSendPlatformMessage(engine as *mut c_void, message.as_ptr().cast()) };

    log_str(&format!(
        "FLUTTER_SETTINGS brightness={brightness} \
text_scale={text_scale:.3} use24h={use_24_hour} ui_mode=0x{ui_mode:x} rc={rc}"
    ));

    rc == 0
}

unsafe extern "C" fn on_configuration_changed(activity: *mut ANativeActivity) {
    log_str("onConfigurationChanged");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    unsafe {
        send_metrics(activity, state);
        send_flutter_settings(activity, state);
    }

    let engine = input_engine(state);

    if engine != 0 {
        let rc = unsafe { FlutterEngineScheduleFrame(engine as *mut c_void) };

        log_str(&format!("CONFIGURATION_FRAME_SCHEDULE rc={rc}"));
    }
}
unsafe fn send_flutter_lifecycle(state: *mut HostState, lifecycle: &str) -> bool {
    if state.is_null() {
        return false;
    }

    let engine = input_engine(state);
    if engine == 0 {
        return false;
    }

    static CHANNEL: &[u8] = b"flutter/lifecycle\0";
    let payload = format!("AppLifecycleState.{lifecycle}");
    let bytes = payload.as_bytes();
    let mut message = vec![0u8; FLUTTER_PLATFORM_MESSAGE_SIZE];

    put_usize(
        &mut message,
        OFF_PLATFORM_MESSAGE_STRUCT_SIZE,
        FLUTTER_PLATFORM_MESSAGE_SIZE,
    );
    put_usize(
        &mut message,
        OFF_PLATFORM_MESSAGE_CHANNEL,
        CHANNEL.as_ptr() as usize,
    );
    put_usize(
        &mut message,
        OFF_PLATFORM_MESSAGE_MESSAGE,
        bytes.as_ptr() as usize,
    );
    put_usize(&mut message, OFF_PLATFORM_MESSAGE_MESSAGE_SIZE, bytes.len());
    put_usize(&mut message, OFF_PLATFORM_MESSAGE_RESPONSE_HANDLE, 0);

    let rc =
        unsafe { FlutterEngineSendPlatformMessage(engine as *mut c_void, message.as_ptr().cast()) };

    log_str(&format!("FLUTTER_LIFECYCLE={lifecycle} rc={rc}"));
    rc == 0
}

fn has_egl_surface(state: *mut HostState) -> bool {
    if state.is_null() {
        return false;
    }

    let egl = match unsafe { &*state }.egl.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    egl.surface != 0
}

unsafe fn replace_window(state: *mut HostState, window: *mut ANativeWindow) {
    if state.is_null() {
        return;
    }

    if !window.is_null() {
        unsafe {
            ANativeWindow_acquire(window);
            ANativeWindow_setBuffersGeometry(window, 0, 0, WINDOW_FORMAT_RGBA_8888);
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

unsafe extern "C" fn on_resume(activity: *mut ANativeActivity) {
    rodin_photo_refresh_permission(activity);
    log_str("onResume");

    if activity.is_null() {
        return;
    }
    let state = unsafe { (*activity).instance.cast::<HostState>() };
    // During a normal foreground recreation onResume arrives before the new
    // ANativeWindow. Resume Flutter only when an onscreen surface is ready.

    if has_egl_surface(state) {
        unsafe {
            send_flutter_settings(activity, state);
            send_flutter_lifecycle(state, "resumed");
        }
    }
}

unsafe extern "C" fn on_pause(activity: *mut ANativeActivity) {
    log_str("onPause");

    if activity.is_null() {
        return;
    }
    let state = unsafe { (*activity).instance.cast::<HostState>() };
    unsafe { send_flutter_lifecycle(state, "inactive") };
}

unsafe extern "C" fn on_stop(activity: *mut ANativeActivity) {
    log_str("onStop");

    if activity.is_null() {
        return;
    }
    let state = unsafe { (*activity).instance.cast::<HostState>() };
    unsafe { send_flutter_lifecycle(state, "paused") };
}

unsafe extern "C" fn on_window_focus_changed(activity: *mut ANativeActivity, focused: c_int) {
    log_str(&format!("window focus={focused}"));

    if activity.is_null() {
        return;
    }
    let state = unsafe { (*activity).instance.cast::<HostState>() };
    if focused == 0 {
        unsafe { send_flutter_lifecycle(state, "inactive") };
    } else if has_egl_surface(state) {
        unsafe { send_flutter_lifecycle(state, "resumed") };
    }
}

unsafe extern "C" fn on_window_created(activity: *mut ANativeActivity, window: *mut ANativeWindow) {
    log_str("native window created");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    unsafe { replace_window(state, window) };

    if let Err(error) = unsafe { init_egl(state, window) } {
        log_str(&format!("EGL_INIT=FAIL {error}"));
        return;
    }

    unsafe { present_launch_background(state, window) };

    match unsafe { start_flutter(activity, state) } {
        Ok(()) => {
            unsafe { send_metrics(activity, state) };
            unsafe { send_flutter_lifecycle(state, "resumed") };

            let engine = input_engine(state);
            if engine != 0 {
                let rc = unsafe { FlutterEngineScheduleFrame(engine as *mut c_void) };
                log_str(&format!("EGL_FOREGROUND_FRAME_SCHEDULE=PASS rc={rc}"));
            }
        }
        Err(error) => log_str(&format!("FLUTTER_START=FAIL {error}")),
    }
}

unsafe extern "C" fn on_window_resized(activity: *mut ANativeActivity, window: *mut ANativeWindow) {
    log_str("native window resized");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    unsafe { replace_window(state, window) };
    unsafe { send_metrics(activity, state) };
}

unsafe extern "C" fn on_window_redraw(activity: *mut ANativeActivity, _: *mut ANativeWindow) {
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

unsafe extern "C" fn on_window_destroyed(activity: *mut ANativeActivity, _: *mut ANativeWindow) {
    log_str("native window destroyed");

    if activity.is_null() {
        return;
    }

    let state = unsafe { (*activity).instance.cast::<HostState>() };

    // Stop Dart frame production before detaching the native surface. Any
    // already in-flight raster frame is still safe because the old EGLSurface
    // is retired, not destroyed from this platform thread.
    unsafe { send_flutter_lifecycle(state, "paused") };
    unsafe { retire_egl_surface(state) };
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

    stop_input_worker(state);
    unsafe { send_flutter_lifecycle(state, "detached") };

    let shared = unsafe { &*state }.vsync.clone();
    shared.alive.store(false, Ordering::Release);

    let choreographer = shared.choreographer.swap(0, Ordering::AcqRel);
    if choreographer != 0 {
        unsafe {
            AChoreographer_unregisterRefreshRateCallback(
                choreographer as *mut AChoreographer,
                refresh_rate_callback,
                Arc::as_ptr(&shared) as *mut c_void,
            );
        }
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
        shared.engine.store(0, Ordering::Release);
        let result = unsafe { FlutterEngineShutdown(engine as *mut c_void) };
        log_str(&format!("FlutterEngineShutdown rc={result}"));
    }

    unsafe { destroy_egl_all(state) };
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
/// Creates the zero-DEX Android native activity and starts the Flutter host.
///
/// # Safety
///
/// Android must pass a valid `ANativeActivity` pointer whose callback table,
/// VM, class reference, asset manager, and paths remain valid for the activity
/// lifecycle. This function must only be invoked by the Android framework.
pub unsafe extern "C" fn ANativeActivity_onCreate(
    activity: *mut ANativeActivity,
    _saved_state: *mut c_void,
    _saved_state_size: usize,
) {
    log_str("ANativeActivity_onCreate entry");

    if activity.is_null() {
        log_str("activity pointer is null");
        return;
    }

    rodin_prepare_launch_window(activity);
    rodin_photo_init(activity);
    rodin_haptic_init(activity);
    log_str("ANativeActivity_onCreate");

    let callbacks = unsafe { (*activity).callbacks };

    if callbacks.is_null() {
        log_str("callback table is null");
        return;
    }

    let state = Box::new(HostState::new());
    let state_ptr = Box::into_raw(state);

    unsafe {
        (*activity).instance = state_ptr.cast();

        let choreographer = AChoreographer_getInstance();
        if !choreographer.is_null() {
            let state_ref: &HostState = &*state_ptr;

            state_ref
                .vsync
                .choreographer
                .store(choreographer as usize, Ordering::Release);

            AChoreographer_registerRefreshRateCallback(
                choreographer,
                refresh_rate_callback,
                Arc::as_ptr(&state_ref.vsync) as *mut c_void,
            );

            log_str("ACHOREOGRAPHER=READY");
        } else {
            log_str("ACHOREOGRAPHER=FAIL");
        }

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
        (*callbacks).on_input_queue_created = Some(on_input_queue_created);
        (*callbacks).on_input_queue_destroyed = Some(on_input_queue_destroyed);
        (*callbacks).on_configuration_changed = Some(on_configuration_changed);
        (*callbacks).on_low_memory = Some(on_low_memory);
    }

    log_str("native callbacks installed");
}
