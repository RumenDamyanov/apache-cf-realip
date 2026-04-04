# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-04

### Added
- Initial project scaffolding
- Rust + C FFI Apache module structure

## [0.1.0] - Unreleased

### Added
- Automatic Cloudflare IPv4/IPv6 CIDR range fetching
- HTTPS with TLS verification
- SHA256 change detection
- Periodic refresh with configurable interval
- Atomic file writes for generated configuration
- Integration with Apache mod_remoteip (RemoteIPTrustedProxy)
- Port of nginx-cf-realip functionality
