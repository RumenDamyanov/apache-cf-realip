// Copyright 2026 Rumen Damyanov <contact@rumenx.com>
// SPDX-License-Identifier: Apache-2.0

//! Atomic config file writer with SHA256 change detection.

use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::Path;

/// Writes RemoteIPTrustedProxy directives to the output file.
///
/// Returns `Ok(true)` if the file was updated, `Ok(false)` if unchanged.
/// Uses SHA256 to detect changes and atomic write (temp + rename) for safety.
pub fn write_config(
    output_path: &str,
    ips: &[String],
    prev_hash: &mut [u8; 32],
    prev_hash_valid: &mut bool,
) -> Result<bool, String> {
    if ips.is_empty() {
        return Err("no IPs to write".to_string());
    }

    // Build content
    let mut content = String::with_capacity(ips.len() * 48);
    content.push_str("# Managed by apache-cf-realip — do not edit manually\n");
    content.push_str(&format!(
        "# Updated: {}\n# Entries: {}\n\n",
        chrono_now(),
        ips.len()
    ));
    for ip in ips {
        content.push_str(&format!("RemoteIPTrustedProxy {}\n", ip));
    }

    // SHA256 check
    let new_hash: [u8; 32] = Sha256::digest(content.as_bytes()).into();

    if *prev_hash_valid && new_hash == *prev_hash {
        return Ok(false); // unchanged
    }

    // Atomic write via temp file + rename
    let tmp_path = format!("{}.tmp", output_path);

    // Ensure parent directory exists
    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent).map_err(|e| format!("create dir: {}", e))?;
    }

    let mut file =
        fs::File::create(&tmp_path).map_err(|e| format!("create temp file: {}", e))?;
    file.write_all(content.as_bytes())
        .map_err(|e| format!("write: {}", e))?;
    file.sync_all()
        .map_err(|e| format!("sync: {}", e))?;
    drop(file);

    fs::rename(&tmp_path, output_path).map_err(|e| format!("rename: {}", e))?;

    *prev_hash = new_hash;
    *prev_hash_valid = true;

    Ok(true) // file updated
}

/// Simple UTC timestamp without external crate dependency.
fn chrono_now() -> String {
    // Use a simple approach — the timestamp will be approximate
    // In production, this gets the current time from the system
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    format!("unix:{}", now.as_secs())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_write_config() {
        let dir = std::env::temp_dir().join("cf_realip_test_write");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let path = dir.join("test.conf");
        let path_str = path.to_str().unwrap();

        let ips = vec!["173.245.48.0/20".to_string(), "2400:cb00::/32".to_string()];
        let mut hash = [0u8; 32];
        let mut valid = false;

        let changed = write_config(path_str, &ips, &mut hash, &mut valid).unwrap();
        assert!(changed);
        assert!(valid);

        let content = fs::read_to_string(path_str).unwrap();
        assert!(content.contains("RemoteIPTrustedProxy 173.245.48.0/20"));
        assert!(content.contains("RemoteIPTrustedProxy 2400:cb00::/32"));
        assert!(content.contains("Managed by apache-cf-realip"));

        // Second call with same IPs should not change
        let unchanged = write_config(path_str, &ips, &mut hash, &mut valid).unwrap();
        assert!(!unchanged);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_write_config_empty() {
        let result = write_config("/tmp/empty.conf", &[], &mut [0u8; 32], &mut false);
        assert!(result.is_err());
    }

    #[test]
    fn test_write_config_detects_change() {
        let dir = std::env::temp_dir().join("cf_realip_test_change");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();

        let path = dir.join("test.conf");
        let path_str = path.to_str().unwrap();
        let mut hash = [0u8; 32];
        let mut valid = false;

        let ips1 = vec!["10.0.0.0/8".to_string()];
        write_config(path_str, &ips1, &mut hash, &mut valid).unwrap();

        let ips2 = vec!["10.0.0.0/8".to_string(), "192.168.0.0/16".to_string()];
        let changed = write_config(path_str, &ips2, &mut hash, &mut valid).unwrap();
        assert!(changed);

        let _ = fs::remove_dir_all(&dir);
    }
}
