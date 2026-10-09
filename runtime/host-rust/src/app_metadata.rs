//! Native package labels for the installed-app chooser; no Java/DEX glue.
use jni::objects::{JObject, JString, JValue};
use std::collections::BTreeMap;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn rodin_host_app_labels(
    input: *const u8,
    len: i32,
    output: *mut u8,
    capacity: i32,
) -> i32 {
    if input.is_null()
        || output.is_null()
        || !(1..=262_144).contains(&len)
        || !(1..=1_048_576).contains(&capacity)
    {
        return -1;
    }
    let bytes = unsafe { std::slice::from_raw_parts(input, len as usize) };
    let Ok(packages) = serde_json::from_slice::<Vec<String>>(bytes) else {
        return -1;
    };
    if packages.len() > 4096 {
        return -1;
    }
    let activity = super::RODIN_PHOTO_ACTIVITY.load(std::sync::atomic::Ordering::Acquire)
        as *mut super::ANativeActivity;
    let Some((vm, object, _)) = super::rodin_photo_vm_and_object(activity) else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };
    let mut labels = BTreeMap::new();
    for package in packages {
        let label: jni::errors::Result<String> = env.with_local_frame(16, |env| {
            let activity = unsafe { JObject::from_raw(object) };
            let manager = env
                .call_method(
                    &activity,
                    "getPackageManager",
                    "()Landroid/content/pm/PackageManager;",
                    &[],
                )?
                .l()?;
            let name = JObject::from(env.new_string(&package)?);
            let info = env
                .call_method(
                    &manager,
                    "getApplicationInfo",
                    "(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;",
                    &[JValue::Object(&name), JValue::Int(0)],
                )?
                .l()?;
            let label = env
                .call_method(
                    &info,
                    "loadLabel",
                    "(Landroid/content/pm/PackageManager;)Ljava/lang/CharSequence;",
                    &[JValue::Object(&manager)],
                )?
                .l()?;
            let string = env
                .call_method(&label, "toString", "()Ljava/lang/String;", &[])?
                .l()?;
            let string = JString::from(string);
            Ok(env.get_string(&string)?.into())
        });
        match label {
            Ok(label) => {
                labels.insert(package, label);
            }
            Err(_) => {
                let _ = env.exception_clear();
            }
        }
    }
    let Ok(raw) = serde_json::to_vec(&labels) else {
        return -1;
    };
    if raw.len() > capacity as usize {
        return -2;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(raw.as_ptr(), output, raw.len());
    }
    raw.len() as i32
}

/// Rasterize real PackageManager drawables (including adaptive icons) through
/// Android Canvas. Icons are requested in bounded batches, never all at once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rodin_host_app_icons(
    input: *const u8,
    len: i32,
    output: *mut u8,
    capacity: i32,
) -> i32 {
    if input.is_null()
        || output.is_null()
        || !(1..=262_144).contains(&len)
        || !(1..=1_048_576).contains(&capacity)
    {
        return -1;
    }
    let bytes = unsafe { std::slice::from_raw_parts(input, len as usize) };
    let Ok(packages) = serde_json::from_slice::<Vec<String>>(bytes) else {
        return -1;
    };
    if packages.len() > 40 {
        return -1;
    }
    let activity = super::RODIN_PHOTO_ACTIVITY.load(std::sync::atomic::Ordering::Acquire)
        as *mut super::ANativeActivity;
    let Some((vm, object, _)) = super::rodin_photo_vm_and_object(activity) else {
        return -1;
    };
    let Ok(mut env) = vm.attach_current_thread() else {
        return -1;
    };
    let mut icons = BTreeMap::new();
    for package in packages {
        let encoded: jni::errors::Result<String> = env.with_local_frame(24, |env| {
            let activity = unsafe { JObject::from_raw(object) };
            let manager = env
                .call_method(
                    &activity,
                    "getPackageManager",
                    "()Landroid/content/pm/PackageManager;",
                    &[],
                )?
                .l()?;
            let name = JObject::from(env.new_string(&package)?);
            let icon = env
                .call_method(
                    &manager,
                    "getApplicationIcon",
                    "(Ljava/lang/String;)Landroid/graphics/drawable/Drawable;",
                    &[JValue::Object(&name)],
                )?
                .l()?;
            let config = env
                .get_static_field(
                    "android/graphics/Bitmap$Config",
                    "ARGB_8888",
                    "Landroid/graphics/Bitmap$Config;",
                )?
                .l()?;
            let bitmap = env
                .call_static_method(
                    "android/graphics/Bitmap",
                    "createBitmap",
                    "(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;",
                    &[JValue::Int(96), JValue::Int(96), JValue::Object(&config)],
                )?
                .l()?;
            let canvas = env.new_object(
                "android/graphics/Canvas",
                "(Landroid/graphics/Bitmap;)V",
                &[JValue::Object(&bitmap)],
            )?;
            env.call_method(
                &icon,
                "setBounds",
                "(IIII)V",
                &[
                    JValue::Int(0),
                    JValue::Int(0),
                    JValue::Int(96),
                    JValue::Int(96),
                ],
            )?;
            env.call_method(
                &icon,
                "draw",
                "(Landroid/graphics/Canvas;)V",
                &[JValue::Object(&canvas)],
            )?;
            let stream = env.new_object("java/io/ByteArrayOutputStream", "()V", &[])?;
            let format = env
                .get_static_field(
                    "android/graphics/Bitmap$CompressFormat",
                    "PNG",
                    "Landroid/graphics/Bitmap$CompressFormat;",
                )?
                .l()?;
            env.call_method(
                &bitmap,
                "compress",
                "(Landroid/graphics/Bitmap$CompressFormat;ILjava/io/OutputStream;)Z",
                &[
                    JValue::Object(&format),
                    JValue::Int(100),
                    JValue::Object(&stream),
                ],
            )?;
            let bytes = env.call_method(&stream, "toByteArray", "()[B", &[])?.l()?;
            let string = env
                .call_static_method(
                    "android/util/Base64",
                    "encodeToString",
                    "([BI)Ljava/lang/String;",
                    &[JValue::Object(&bytes), JValue::Int(2)],
                )?
                .l()?;
            let _ = env.call_method(&bitmap, "recycle", "()V", &[]);
            Ok(env.get_string(&JString::from(string))?.into())
        });
        match encoded {
            Ok(icon) => {
                icons.insert(package, icon);
            }
            Err(_) => {
                let _ = env.exception_clear();
            }
        }
    }
    let Ok(raw) = serde_json::to_vec(&icons) else {
        return -1;
    };
    if raw.len() > capacity as usize {
        return -2;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(raw.as_ptr(), output, raw.len());
    }
    raw.len() as i32
}
