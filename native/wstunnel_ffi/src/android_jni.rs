//! JNI bindings for Android (`System.loadLibrary("wstunnel_ffi")`).

use jni::objects::{JClass, JString};
use jni::sys::{jint, jstring};
use jni::JNIEnv;
use std::ffi::CString;
use std::os::raw::c_char;
use std::{ptr, slice};

use crate::{wstunnel_client_is_running, wstunnel_client_start, wstunnel_client_stop};

#[no_mangle]
pub extern "system" fn Java_com_petrixon_vpn_WstunnelFfi_nativeStart(
    mut env: JNIEnv,
    _class: JClass,
    config_json: JString,
) -> jstring {
    let json: String = match env.get_string(&config_json) {
        Ok(s) => s.into(),
        Err(e) => {
            return env
                .new_string(format!("jni: bad config string: {e}"))
                .map(|s| s.into_raw())
                .unwrap_or(ptr::null_mut());
        }
    };
    let c_json = match CString::new(json) {
        Ok(s) => s,
        Err(_) => {
            return env
                .new_string("jni: config contains NUL")
                .map(|s| s.into_raw())
                .unwrap_or(ptr::null_mut());
        }
    };

    let mut err = vec![0 as c_char; 512];
    let rc = unsafe {
        wstunnel_client_start(c_json.as_ptr(), err.as_mut_ptr(), err.len())
    };
    if rc == 0 {
        return ptr::null_mut();
    }
    let len = err.iter().position(|&b| b == 0).unwrap_or(err.len());
    let msg = unsafe {
        let bytes = slice::from_raw_parts(err.as_ptr() as *const u8, len);
        String::from_utf8_lossy(bytes).into_owned()
    };
    let out = if msg.is_empty() {
        format!("wstunnel start failed ({rc})")
    } else {
        format!("wstunnel start failed ({rc}): {msg}")
    };
    env.new_string(out)
        .map(|s| s.into_raw())
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_com_petrixon_vpn_WstunnelFfi_nativeStop(
    _env: JNIEnv,
    _class: JClass,
) {
    wstunnel_client_stop();
}

#[no_mangle]
pub extern "system" fn Java_com_petrixon_vpn_WstunnelFfi_nativeIsRunning(
    _env: JNIEnv,
    _class: JClass,
) -> jint {
    wstunnel_client_is_running()
}
