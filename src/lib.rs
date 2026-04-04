// Copyright 2026 Rumen Damyanov <contact@rumenx.com>
// SPDX-License-Identifier: Apache-2.0

//! apache-cf-realip — Rust core library
//!
//! Fetches Cloudflare IP ranges and writes RemoteIPTrustedProxy directives.
//! Exported as a static library for linking with the C Apache module shim.

pub mod fetch;
pub mod writer;

use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::Mutex;

/// Global state for the update loop, protected by a mutex.
struct UpdateState {
    prev_hash: [u8; 32],
    prev_hash_valid: bool,
    failure_count: u32,
}

static STATE: Mutex<UpdateState> = Mutex::new(UpdateState {
    prev_hash: [0u8; 32],
    prev_hash_valid: false,
    failure_count: 0,
});

/// Fetches Cloudflare IPs and writes the config file.
///
/// # Safety
/// All pointer parameters must be valid, non-null, NUL-terminated C strings.
///
/// Returns:
///  1  = file updated
///  0  = file unchanged (same content)
/// -1  = error
#[no_mangle]
pub unsafe extern "C" fn cf_realip_fetch_and_write(
    url_v4: *const c_char,
    url_v6: *const c_char,
    output_path: *const c_char,
    fetch_ipv6: i32,
) -> i32 {
    let url_v4 = match ptr_to_str(url_v4) {
        Some(s) => s,
        None => return -1,
    };
    let output = match ptr_to_str(output_path) {
        Some(s) => s,
        None => return -1,
    };

    // Fetch IPv4 list
    let mut all_ips = match fetch::fetch_ips(url_v4) {
        Ok(ips) => ips,
        Err(e) => {
            eprintln!("cf_realip: IPv4 fetch failed: {}", e);
            if let Ok(mut state) = STATE.lock() {
                state.failure_count += 1;
            }
            return -1;
        }
    };

    // Fetch IPv6 list if enabled
    if fetch_ipv6 != 0 {
        if let Some(url_v6_str) = ptr_to_str(url_v6) {
            if !url_v6_str.is_empty() {
                match fetch::fetch_ips(url_v6_str) {
                    Ok(ips) => all_ips.extend(ips),
                    Err(e) => {
                        eprintln!("cf_realip: IPv6 fetch failed: {}", e);
                        // Continue with IPv4 only
                    }
                }
            }
        }
    }

    // Write config file
    let mut state = match STATE.lock() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    let UpdateState { ref mut prev_hash, ref mut prev_hash_valid, ref mut failure_count } = *state;

    match writer::write_config(output, &all_ips, prev_hash, prev_hash_valid) {
        Ok(true) => {
            *failure_count = 0;
            1 // updated
        }
        Ok(false) => {
            *failure_count = 0;
            0 // unchanged
        }
        Err(e) => {
            eprintln!("cf_realip: write failed: {}", e);
            *failure_count += 1;
            -1
        }
    }
}

/// Returns the current failure count.
#[no_mangle]
pub extern "C" fn cf_realip_failure_count() -> u32 {
    STATE.lock().map(|s| s.failure_count).unwrap_or(0)
}

/// Resets the failure counter.
#[no_mangle]
pub extern "C" fn cf_realip_reset_state() {
    if let Ok(mut s) = STATE.lock() {
        s.prev_hash = [0u8; 32];
        s.prev_hash_valid = false;
        s.failure_count = 0;
    }
}

/// Returns the module version as a C string. Caller must NOT free the result.
#[no_mangle]
pub extern "C" fn cf_realip_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

/// Helper: convert a C string pointer to a Rust &str.
unsafe fn ptr_to_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok()
}
