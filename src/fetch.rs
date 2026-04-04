// Copyright 2026 Rumen Damyanov <contact@rumenx.com>
// SPDX-License-Identifier: Apache-2.0

//! HTTP fetching and CIDR parsing for Cloudflare IP ranges.

use std::net::IpAddr;

const USER_AGENT: &str = "apache-cf-remoteip/0.1.0";

/// Fetches a URL and parses the response into a list of validated CIDR strings.
pub fn fetch_ips(url: &str) -> Result<Vec<String>, String> {
    let resp = ureq::agent()
        .get(url)
        .set("User-Agent", USER_AGENT)
        .call()
        .map_err(|e| format!("fetch {}: {}", url, e))?;

    if resp.status() != 200 {
        return Err(format!("fetch {}: HTTP {}", url, resp.status()));
    }

    let body = resp
        .into_string()
        .map_err(|e| format!("read body: {}", e))?;

    parse_cidr_list(&body)
}

/// Parses a newline-separated list of CIDRs, validating each entry.
fn parse_cidr_list(text: &str) -> Result<Vec<String>, String> {
    let mut ips = Vec::new();

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        if is_valid_cidr(trimmed) {
            ips.push(trimmed.to_string());
        }
    }

    Ok(ips)
}

/// Validates that a string is a valid IP address or CIDR notation.
fn is_valid_cidr(s: &str) -> bool {
    // Try as CIDR
    if s.parse::<ipnet::IpNet>().is_ok() {
        return true;
    }
    // Try as plain IP
    s.parse::<IpAddr>().is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cidr_list() {
        let input = "# comment\n173.245.48.0/20\n103.21.244.0/22\n\n# blank above\n2400:cb00::/32\n";
        let result = parse_cidr_list(input).unwrap();
        assert_eq!(result.len(), 3);
        assert_eq!(result[0], "173.245.48.0/20");
        assert_eq!(result[2], "2400:cb00::/32");
    }

    #[test]
    fn test_parse_cidr_list_invalid() {
        let input = "173.245.48.0/20\nnot-a-cidr\n10.0.0.1\n";
        let result = parse_cidr_list(input).unwrap();
        assert_eq!(result.len(), 2); // CIDR + plain IP, skips invalid
    }

    #[test]
    fn test_is_valid_cidr() {
        assert!(is_valid_cidr("173.245.48.0/20"));
        assert!(is_valid_cidr("2400:cb00::/32"));
        assert!(is_valid_cidr("10.0.0.1"));
        assert!(!is_valid_cidr("not-valid"));
        assert!(!is_valid_cidr(""));
    }
}
