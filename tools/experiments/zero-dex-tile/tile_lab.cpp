// NEESCHAL's tile lab: absolutely no charging commands, no daemon connection,
// no DEX generation, no class redefinition, and no SystemUI injection.
// A debug-only native JVMTI breakpoint observes the boot TileService methods.
#include <android/log.h>
#include <android/native_activity.h>
#include <jvmti.h>
#include <cstdio>

#define LOG(...) __android_log_print(ANDROID_LOG_INFO, "RodinTileLab", __VA_ARGS__)

static jmethodID click_method = nullptr;
static jmethodID listen_method = nullptr;
static bool selected = false; // HARmless in-memory lab state, NOT bypass status.
static unsigned clicks = 0;
static bool agent_ready = false;
static thread_local bool inside_callback = false;

static bool clear_exception(JNIEnv* env, const char* stage) {
    if (!env->ExceptionCheck()) return false;
    LOG("JNI_EXCEPTION stage=%s", stage);
    env->ExceptionDescribe();
    env->ExceptionClear();
    return true;
}

static void update_test_tile(JNIEnv* env, jobject receiver) {
    jclass service = env->GetObjectClass(receiver);
    jmethodID get = env->GetMethodID(service, "getQsTile", "()Landroid/service/quicksettings/Tile;");
    if (!get || clear_exception(env, "getQsTile method")) return;
    jobject tile = env->CallObjectMethod(receiver, get);
    if (clear_exception(env, "getQsTile") || !tile) return;
    jclass klass = env->GetObjectClass(tile);
    jmethodID set_state = env->GetMethodID(klass, "setState", "(I)V");
    jmethodID set_subtitle = env->GetMethodID(klass, "setSubtitle", "(Ljava/lang/CharSequence;)V");
    jmethodID update = env->GetMethodID(klass, "updateTile", "()V");
    if (!set_state || !set_subtitle || !update || clear_exception(env, "tile methods")) return;
    char label[96];
    std::snprintf(label, sizeof(label), "TEST ONLY %s | taps %u", selected ? "ON" : "OFF", clicks);
    jstring text = env->NewStringUTF(label);
    env->CallVoidMethod(tile, set_state, selected ? 2 : 1);
    env->CallVoidMethod(tile, set_subtitle, text);
    env->CallVoidMethod(tile, update);
    if (!clear_exception(env, "updateTile")) LOG("TILE_UPDATED state=%d clicks=%u", selected, clicks);
}

static void JNICALL breakpoint(jvmtiEnv* ti, JNIEnv* env, jthread thread,
                               jmethodID method, jlocation) {
    if (inside_callback || (method != click_method && method != listen_method)) return;
    inside_callback = true;
    jobject receiver = nullptr;
    jvmtiError error = ti->GetLocalInstance(thread, 0, &receiver);
    LOG("CALLBACK kind=%s receiver_error=%d", method == click_method ? "click" : "listen", error);
    if (error == JVMTI_ERROR_NONE && receiver && env->PushLocalFrame(24) == JNI_OK) {
        if (method == click_method) {
            selected = !selected;
            ++clicks;
            LOG("TEST_CLICK selected=%d clicks=%u (NO HARDWARE WRITE)", selected, clicks);
        }
        update_test_tile(env, receiver);
        env->PopLocalFrame(nullptr);
    }
    if (receiver) env->DeleteLocalRef(receiver);
    inside_callback = false;
}

static jint install_callbacks(jvmtiEnv* ti, JNIEnv* env) {
    if (agent_ready) { LOG("AGENT_ALREADY_READY"); return JNI_OK; }
    jvmtiCapabilities capabilities{};
    capabilities.can_generate_breakpoint_events = 1;
    capabilities.can_access_local_variables = 1;
    jvmtiError result = ti->AddCapabilities(&capabilities);
    LOG("ADD_CAPABILITIES result=%d", result);
    if (result != JVMTI_ERROR_NONE) return JNI_ERR;
    jclass service = env->FindClass("android/service/quicksettings/TileService");
    if (!service || clear_exception(env, "FindClass TileService")) return JNI_ERR;
    click_method = env->GetMethodID(service, "onClick", "()V");
    listen_method = env->GetMethodID(service, "onStartListening", "()V");
    env->DeleteLocalRef(service);
    if (!click_method || !listen_method || clear_exception(env, "callback methods")) return JNI_ERR;
    jvmtiEventCallbacks callbacks{};
    callbacks.Breakpoint = breakpoint;
    result = ti->SetEventCallbacks(&callbacks, sizeof(callbacks));
    if (result != JVMTI_ERROR_NONE) { LOG("EVENT_CALLBACK_FAILED result=%d", result); return JNI_ERR; }
    result = ti->SetBreakpoint(click_method, 0);
    LOG("CLICK_BREAKPOINT result=%d", result);
    if (result != JVMTI_ERROR_NONE) return JNI_ERR;
    result = ti->SetBreakpoint(listen_method, 0);
    LOG("LISTEN_BREAKPOINT result=%d", result);
    if (result != JVMTI_ERROR_NONE) {
        ti->ClearBreakpoint(click_method, 0);
        return JNI_ERR;
    }
    result = ti->SetEventNotificationMode(JVMTI_ENABLE, JVMTI_EVENT_BREAKPOINT, nullptr);
    LOG("AGENT_READY result=%d", result);
    agent_ready = result == JVMTI_ERROR_NONE;
    return result == JVMTI_ERROR_NONE ? JNI_OK : JNI_ERR;
}

extern "C" JNIEXPORT jint JNICALL Agent_OnAttach(JavaVM* vm, char*, void*) {
    LOG("AGENT_ATTACH entry");
    jvmtiEnv* ti = nullptr;
    jint error = vm->GetEnv(reinterpret_cast<void**>(&ti), JVMTI_VERSION_1_2);
    if (error != JNI_OK || !ti) { LOG("JVMTI_UNAVAILABLE error=%d", error); return JNI_ERR; }
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    return install_callbacks(ti, env);
}

static void JNICALL vm_init(jvmtiEnv* ti, JNIEnv* env, jthread) {
    LOG("STARTUP_VM_INIT");
    LOG("STARTUP_INSTALL result=%d", install_callbacks(ti, env));
}

extern "C" JNIEXPORT jint JNICALL Agent_OnLoad(JavaVM* vm, char*, void*) {
    LOG("STARTUP_AGENT_ONLOAD");
    jvmtiEnv* ti = nullptr;
    jint error = vm->GetEnv(reinterpret_cast<void**>(&ti), JVMTI_VERSION_1_2);
    if (error != JNI_OK || !ti) { LOG("STARTUP_JVMTI_UNAVAILABLE error=%d", error); return JNI_ERR; }
    jvmtiEventCallbacks callbacks{};
    callbacks.VMInit = vm_init;
    jvmtiError result = ti->SetEventCallbacks(&callbacks, sizeof(callbacks));
    if (result != JVMTI_ERROR_NONE) return JNI_ERR;
    result = ti->SetEventNotificationMode(JVMTI_ENABLE, JVMTI_EVENT_VM_INIT, nullptr);
    return result == JVMTI_ERROR_NONE ? JNI_OK : JNI_ERR;
}

extern "C" JNIEXPORT void ANativeActivity_onCreate(ANativeActivity* activity, void*, size_t) {
    if (agent_ready) { ANativeActivity_finish(activity); return; }
    JNIEnv* env = activity->env;
    // The native agent is loaded only in this isolated, debuggable lab process.
    jclass activity_class = env->GetObjectClass(activity->clazz);
    jmethodID loader_method = env->GetMethodID(activity_class, "getClassLoader", "()Ljava/lang/ClassLoader;");
    if (!loader_method || clear_exception(env, "getClassLoader method")) return;
    jobject loader = env->CallObjectMethod(activity->clazz, loader_method);
    jclass debug = env->FindClass("android/os/Debug");
    jmethodID attach = debug ? env->GetStaticMethodID(debug, "attachJvmtiAgent",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V") : nullptr;
    if (!attach || clear_exception(env, "attachJvmtiAgent method")) return;
    jstring library = env->NewStringUTF("librodin_tile_lab.so");
    env->CallStaticVoidMethod(debug, attach, library, nullptr, loader);
    bool failed = clear_exception(env, "attachJvmtiAgent");
    LOG("ACTIVITY_ATTACHED success=%d; this experiment never controls charging", !failed);
    ANativeActivity_finish(activity);
}
