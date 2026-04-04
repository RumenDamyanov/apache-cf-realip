/*
 * Copyright 2026 Rumen Damyanov <contact@rumenx.com>
 * SPDX-License-Identifier: Apache-2.0
 *
 * mod_cf_remoteip — Apache module shim header
 */

#ifndef MOD_CF_REMOTEIP_H
#define MOD_CF_REMOTEIP_H

#include "httpd.h"
#include "http_config.h"
#include "http_log.h"
#include "http_protocol.h"
#include "ap_config.h"
#include "apr_strings.h"
#include "apr_thread_proc.h"
#include "apr_thread_mutex.h"

#define CF_REMOTEIP_VERSION "0.1.0"

#define CF_REMOTEIP_DEFAULT_URL_V4    "https://www.cloudflare.com/ips-v4"
#define CF_REMOTEIP_DEFAULT_URL_V6    "https://www.cloudflare.com/ips-v6"
#define CF_REMOTEIP_DEFAULT_REFRESH   3600    /* seconds */
#define CF_REMOTEIP_MIN_REFRESH       300     /* 5 minutes */
#define CF_REMOTEIP_DEFAULT_OUTPUT    "/etc/apache2/conf-available/cf-trusted-proxies.conf"

/* Server configuration */
typedef struct {
    const char *source_url_v4;
    const char *source_url_v6;
    const char *output_path;
    int         refresh_interval;      /* seconds */
    int         fetch_ipv6;            /* 1=yes, 0=no */
    int         enabled;               /* global enable flag */
} cf_remoteip_server_conf;

/* Rust FFI declarations */
extern int  cf_remoteip_fetch_and_write(const char *url_v4, const char *url_v6,
                                         const char *output_path, int fetch_ipv6);
extern unsigned int cf_remoteip_failure_count(void);
extern void cf_remoteip_reset_state(void);
extern const char *cf_remoteip_version(void);

#endif /* MOD_CF_REMOTEIP_H */
