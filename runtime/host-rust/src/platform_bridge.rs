//! Small Android framework adapter. No charging sysfs writes and no Flutter UI
//! work on Android's main thread. NEESCHAL's rule: report state, don't invent it.
use jni::{
    JNIEnv,
    objects::JClass,
    sys::{jboolean, jfloat, jint},
};
use std::sync::{
    Mutex, OnceLock,
    atomic::{AtomicI32, Ordering},
};

static ACTIVITY: OnceLock<Mutex<Option<(jni::JavaVM, jni::objects::GlobalRef)>>> = OnceLock::new();
static BACK_EVENT: AtomicI32 = AtomicI32::new(0);
static OPEN_BYPASS: AtomicI32 = AtomicI32::new(0);

#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_neeschal_rodinessential_RodinActivity_nativeOpenBypassSettings(_: JNIEnv, _: JClass) {
    OPEN_BYPASS.store(1, Ordering::Release);
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_consume_bypass_settings_request() -> i32 {
    OPEN_BYPASS.swap(0, Ordering::AcqRel)
}
// Registration and invocation share the lock: Dart can safely unregister before
// closing its callback, including when Android delivers a final lifecycle event.
static BACK_LISTENER: Mutex<Option<extern "C" fn(i32)>> = Mutex::new(None);

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_set_back_listener(listener: Option<extern "C" fn(i32)>) {
    *BACK_LISTENER.lock().unwrap() = listener;
    BACK_EVENT.store(0, Ordering::Release);
    super::RODIN_BACK_PENDING.store(false, Ordering::Release);
}

pub fn init(activity: *mut super::ANativeActivity) {
    let Some((vm, object, _)) = super::rodin_photo_vm_and_object(activity) else {
        return;
    };
    let reference = {
        let Ok(env) = vm.attach_current_thread() else {
            return;
        };
        let object = unsafe { jni::objects::JObject::from_raw(object) };
        env.new_global_ref(&object).ok()
    };
    if let Some(reference) = reference {
        *ACTIVITY.get_or_init(|| Mutex::new(None)).lock().unwrap() = Some((vm, reference));
    }
}
pub fn clear() {
    if let Some(activity) = ACTIVITY.get() {
        *activity.lock().unwrap() = None;
    }
    BACK_EVENT.store(0, Ordering::Release);
}
pub fn refresh_back() {
    let Some(activity) = ACTIVITY.get() else {
        return;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return;
    };
    let _ = env.with_local_frame(4, |env| -> jni::errors::Result<()> {
        let class = env.get_object_class(reference.as_obj())?;
        env.call_static_method(class, "refreshBackFromNative", "()V", &[])?;
        Ok(())
    });
    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_consume_back_gesture() -> i32 {
    BACK_EVENT.swap(0, Ordering::AcqRel)
}
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_neeschal_rodinessential_RodinActivity_nativeInterceptBack(
    _: JNIEnv,
    _: JClass,
) -> jboolean {
    super::RODIN_BACK_INTERCEPT.load(Ordering::Acquire) as jboolean
}
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_neeschal_rodinessential_RodinActivity_nativeBack(
    _: JNIEnv,
    _: JClass,
    phase: jint,
    progress: jfloat,
    edge: jint,
) {
    if !(1..=4).contains(&phase) || !progress.is_finite() {
        return;
    }
    if phase != 2 {
        super::log_str(&format!(
            "PLATFORM_BACK phase={phase} progress={progress} edge={edge}"
        ));
    }
    let value = (progress.clamp(0.0, 1.0) * 10000.0).round() as i32;
    // Single atomic packet: phase, edge and progress cannot come from different frames.
    let packet = (phase << 16) | ((edge & 1) << 15) | value;
    let listener = BACK_LISTENER.lock().unwrap();
    if let Some(callback) = *listener {
        callback(packet);
        return;
    }
    BACK_EVENT.store(packet, Ordering::Release);
    if phase == 4 && super::RODIN_BACK_INTERCEPT.load(Ordering::Acquire) {
        super::RODIN_BACK_PENDING.store(true, Ordering::Release);
    }
}
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_neeschal_rodinessential_BypassTileService_nativeStart(_: JNIEnv, _: JClass) {
    super::backend_bridge::rodin_backend_start();
}
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_neeschal_rodinessential_BypassTileService_nativeSnapshot(_: JNIEnv, _: JClass) -> jint {
    use super::backend_bridge::*;
    let phase = rodin_backend_extended_get(120);
    let confirmed = super::bypass_tile::direct_power_confirmed(
        phase, rodin_backend_extended_get(115), rodin_backend_get_usb_online(),
        rodin_backend_get_battery_current_ua(),
    );
    i32::from(rodin_backend_ready() == 1)
        | (i32::from(rodin_backend_extended_get(112) == 1) << 1)
        | (i32::from(rodin_backend_extended_get(114) == 1) << 2)
        | (i32::from(confirmed) << 3)
        | (i32::from(rodin_backend_get_charging_write_state() == 1) << 4)
        | (i32::from(rodin_backend_extended_get(116) == 1) << 5)
        | (i32::from(rodin_backend_extended_get(121) > 0 || rodin_backend_get_charging_write_state() < 0 || phase == 5) << 6)
        | ((phase.clamp(0, 15)) << 7)
}
#[unsafe(no_mangle)]
pub extern "system" fn Java_io_github_neeschal_rodinessential_BypassTileService_nativeToggle(_: JNIEnv, _: JClass) -> jboolean {
    use super::backend_bridge::*;
    if rodin_backend_ready() != 1 || rodin_backend_extended_get(112) != 1
        || rodin_backend_extended_get(116) != 1 || rodin_backend_get_charging_write_state() == 1 { return 0; }
    let saved = rodin_backend_extended_get(114);
    if !matches!(saved, 0 | 1) { return 0; }
    rodin_backend_set_bypass_charging(1 - saved) as jboolean
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_bluetooth_status() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(8, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let status = env
            .call_static_method(class, "audioBluetoothStatus", "()I", &[])?
            .i()?;
        Ok(status)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_permission() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(8, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        env.call_static_method(class, "requestAudioBluetoothPermission", "()I", &[])?
            .i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_permission_generation() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(8, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        env.call_static_method(class, "audioPermissionGeneration", "()I", &[])?
            .i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    result.unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_refresh_device() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(8, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        env.call_static_method(class, "audioRefreshConnectedDevice", "()I", &[])?
            .i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}


#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_apply_codec(
    codec_type: i32,
    sample_rate: i32,
    bits_per_sample: i32,
) -> i32 {
    rodin_host_audio_request_apply_codec_with_quality(
        codec_type,
        sample_rate,
        bits_per_sample,
        -1,
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_apply_codec_with_quality(
    codec_type: i32,
    sample_rate: i32,
    bits_per_sample: i32,
    ldac_quality: i32,
) -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioRequestApplyCodecPreference",
            "(IIII)I",
            &[
                jni::objects::JValue::Int(codec_type),
                jni::objects::JValue::Int(sample_rate),
                jni::objects::JValue::Int(bits_per_sample),
                jni::objects::JValue::Int(ldac_quality),
            ],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_cancel_pending_apply() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioCancelPendingCodecApply",
            "()I",
            &[],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_delete_profile(
    connection_generation: i32,
) -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let address_value = env.call_static_method(
            &class,
            "audioConnectedDeviceAddress",
            "()Ljava/lang/String;",
            &[],
        )?.l()?;

        if address_value.is_null() {
            return Ok(0);
        }

        let address = jni::objects::JString::from(address_value);
        let address_text: String = env.get_string(&address)?.into();

        if address_text.is_empty() {
            return Ok(0);
        }

        let address_object = jni::objects::JValue::Object(address.as_ref());

        let value = env.call_static_method(
            class,
            "audioRequestDeleteDeviceProfile",
            "(ILjava/lang/String;)I",
            &[
                jni::objects::JValue::Int(connection_generation),
                address_object,
            ],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_set_auto_restore(
    connection_generation: i32,
    enabled: i32,
) -> i32 {
    if connection_generation < 0 || (enabled != 0 && enabled != 1) {
        return 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;

        let address_value = env.call_static_method(
            &class,
            "audioConnectedDeviceAddress",
            "()Ljava/lang/String;",
            &[],
        )?.l()?;

        if address_value.is_null() {
            return Ok(0);
        }

        let address = jni::objects::JString::from(address_value);
        let address_text: String = env.get_string(&address)?.into();

        if address_text.is_empty() {
            return Ok(0);
        }

        let value = env.call_static_method(
            class,
            "audioRequestSetAutoRestore",
            "(IZLjava/lang/String;)I",
            &[
                jni::objects::JValue::Int(connection_generation),
                jni::objects::JValue::Bool(if enabled == 1 { 1 } else { 0 }),
                jni::objects::JValue::Object(address.as_ref()),
            ],
        )?;

        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_save_profile(
    codec_type: i32,
    sample_rate: i32,
    bits_per_sample: i32,
    connection_generation: i32,
) -> i32 {
    rodin_host_audio_request_save_profile_with_quality(
        codec_type,
        sample_rate,
        bits_per_sample,
        -1,
        connection_generation,
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_save_profile_with_quality(
    codec_type: i32,
    sample_rate: i32,
    bits_per_sample: i32,
    ldac_quality: i32,
    connection_generation: i32,
) -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioRequestSaveDeviceProfile",
            "(IIIII)I",
            &[
                jni::objects::JValue::Int(codec_type),
                jni::objects::JValue::Int(sample_rate),
                jni::objects::JValue::Int(bits_per_sample),
                jni::objects::JValue::Int(ldac_quality),
                jni::objects::JValue::Int(connection_generation),
            ],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_apply_codec_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env
            .call_static_method(class, "audioApplyCodecResult", "()Ljava/lang/String;", &[])?
            .l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_save_profile_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env
            .call_static_method(class, "audioSaveDeviceProfileResult", "()Ljava/lang/String;", &[])?
            .l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_auto_restore_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioAutoRestoreResult",
            "()Ljava/lang/String;",
            &[],
        )?.l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_delete_profile_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env
            .call_static_method(class, "audioDeleteDeviceProfileResult", "()Ljava/lang/String;", &[])?
            .l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_saved_profile_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env
            .call_static_method(
                class,
                "audioSavedProfileQueryResult",
                "()Ljava/lang/String;",
                &[],
            )?
            .l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_connection_generation() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioConnectionGeneration",
            "()I",
            &[],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    result.unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_saved_profile() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioRequestSavedProfile",
            "()I",
            &[],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_codec_diagnostic() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioRequestCodecDiagnostic",
            "()I",
            &[],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_codec_diagnostic_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioCodecDiagnosticResult",
            "()Ljava/lang/String;",
            &[],
        )?.l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}


#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_companion_association() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(8, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioRequestCompanionAssociation",
            "()I",
            &[],
        )?;
        value.i()
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_request_companion_status() -> i32 {
    let Some(activity) = ACTIVITY.get() else {
        return 0;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return 0;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return 0;
    };

    let result = env.with_local_frame(8, |env| -> jni::errors::Result<i32> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioRequestCompanionAssociationStatus",
            "()I",
            &[],
        )?.i()?;
        Ok(value)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return 0;
    }

    result.unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_companion_status_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioCompanionAssociationStatusResult",
            "()Ljava/lang/String;",
            &[],
        )?.l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_companion_association_result(
    buffer: *mut u8,
    capacity: usize,
) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env.call_static_method(
            class,
            "audioCompanionAssociationResult",
            "()Ljava/lang/String;",
            &[],
        )?.l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(result) = result else {
        return -1;
    };

    let bytes = result.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn rodin_host_audio_device_name(buffer: *mut u8, capacity: usize) -> i32 {
    if buffer.is_null() || capacity == 0 || capacity > 4096 {
        return -1;
    }

    // Always initialize the caller's output buffer.
    unsafe {
        *buffer = 0;
    }

    let Some(activity) = ACTIVITY.get() else {
        return -1;
    };
    let guard = activity.lock().unwrap();
    let Some((vm, reference)) = guard.as_ref() else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };

    let result = env.with_local_frame(16, |env| -> jni::errors::Result<String> {
        let class = env.get_object_class(reference.as_obj())?;
        let value = env
            .call_static_method(
                class,
                "audioConnectedDeviceName",
                "()Ljava/lang/String;",
                &[],
            )?
            .l()?;

        if value.is_null() {
            return Ok(String::new());
        }

        let java_string = jni::objects::JString::from(value);
        let text: String = env.get_string(&java_string)?.into();
        Ok(text)
    });

    if env.exception_check().unwrap_or(false) {
        let _ = env.exception_clear();
        return -1;
    }

    let Ok(name) = result else {
        return -1;
    };
    let bytes = name.as_bytes();

    if bytes.len() >= capacity {
        return -1;
    }

    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer, bytes.len());
        *buffer.add(bytes.len()) = 0;
    }

    bytes.len() as i32
}
