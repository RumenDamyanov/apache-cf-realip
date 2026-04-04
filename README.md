[![License](https://img.shields.io/github/license/RumenDamyanov/apache-cf-realip?label=License)](LICENSE.md)

# Apache CF RealIP

An Apache httpd module that automatically fetches Cloudflare IPv4 and IPv6 CIDR ranges and generates `RemoteIPTrustedProxy` configuration for `mod_remoteip`. Port of [nginx-cf-realip](https://github.com/RumenDamyanov/nginx-cf-realip) for Apache.

**Implementation:** Rust core with thin C FFI shim for Apache module registration.

## Features

- **Automatic Cloudflare IP fetching** — downloads authoritative IPv4/IPv6 CIDR lists
- **HTTPS with TLS verification** — secure fetching with certificate validation
- **SHA256 change detection** — only rewrites config when IPs actually change
- **Periodic refresh** — configurable update interval (minimum 5 minutes)
- **Atomic file writes** — no partial/corrupt config files
- **Integrates with mod_remoteip** — generates `RemoteIPTrustedProxy` directives
- **Memory safe** — Rust core prevents buffer overflows and use-after-free

## Quick Start

### 1. Install

**Debian/Ubuntu:**
```bash
# Add the OBS repository (see Installation Guide for details)
apt install apache-cf-realip
```

### 2. Configure Apache

```apache
LoadModule cf_realip_module modules/mod_cf_realip.so
LoadModule remoteip_module modules/mod_remoteip.so

# Cloudflare IP list settings
CfRemoteipEnabled on
CfRemoteipRefreshInterval 3600
CfRemoteipOutputPath /etc/apache2/conf-available/cf-trusted-proxies.conf

# Include the generated trusted proxy list
Include /etc/apache2/conf-available/cf-trusted-proxies.conf

RemoteIPHeader CF-Connecting-IP
```

### 3. Verify

```bash
apachectl configtest && apachectl graceful
```

## Configuration Reference

| Directive | Context | Default | Description |
|-----------|---------|---------|-------------|
| `CfRemoteipEnabled` | server config | `off` | Enable/disable Cloudflare IP fetching |
| `CfRemoteipSourceUrl` | server config | Cloudflare official | IPv4 list URL |
| `CfRemoteipSourceUrlV6` | server config | Cloudflare official | IPv6 list URL |
| `CfRemoteipRefreshInterval` | server config | `3600` | Refresh interval in seconds (min: 300) |
| `CfRemoteipOutputPath` | server config | — | Where to write the generated config |

## Building from Source

```bash
# Build Rust library
cargo build --release

# Build and install Apache module
make
sudo make install
```

## Related Projects

| Module | Description | GitHub |
|--------|-------------|--------|
| **apache-gone** | Return HTTP 410 Gone for permanently removed URIs | [GitHub](https://github.com/RumenDamyanov/apache-gone) |
| **apache-torblocker** | Control access from Tor exit nodes | [GitHub](https://github.com/RumenDamyanov/apache-torblocker) |
| **apache-waf** | IP/CIDR-based access control with named lists | [GitHub](https://github.com/RumenDamyanov/apache-waf) |

### nginx Counterpart

| nginx Module | Apache Module |
|-------------|---------------|
| [nginx-cf-realip](https://github.com/RumenDamyanov/nginx-cf-realip) | **apache-cf-realip** (this project) |

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
