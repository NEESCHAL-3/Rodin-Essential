// Run the native cache/protocol tests on a host without linking Android or
// Flutter. The URL bridge is unrelated to palette transactions and is stubbed.
#![allow(dead_code)]
fn rodin_host_open_url_jni(_: i32) -> bool {
    false
}

#[path = "../../runtime/host-rust/src/backend_bridge.rs"]
mod backend_bridge;
