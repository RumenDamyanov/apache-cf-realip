/*
 * Copyright 2026 Rumen Damyanov <contact@rumenx.com>
 * SPDX-License-Identifier: Apache-2.0
 *
 * mod_cf_realip — Apache module for automatic Cloudflare IP fetching
 *
 * Thin C shim that integrates with Apache's module API. All business logic
 * (HTTP fetching, CIDR parsing, SHA256, file writing) is in the Rust library.
 */

#include "mod_cf_realip.h"

#include <unistd.h>

module AP_MODULE_DECLARE_DATA cf_realip_module;

/* Background thread state */
static apr_thread_t *update_thread = NULL;
static volatile int  shutdown_flag = 0;

/* ----------------------------------------------------------------
 * Configuration handling
 * ---------------------------------------------------------------- */

static void *
create_server_conf(apr_pool_t *p, server_rec *s)
{
    cf_realip_server_conf *conf = apr_pcalloc(p, sizeof(*conf));

    conf->source_url_v4    = CF_REALIP_DEFAULT_URL_V4;
    conf->source_url_v6    = CF_REALIP_DEFAULT_URL_V6;
    conf->output_path      = CF_REALIP_DEFAULT_OUTPUT;
    conf->refresh_interval = CF_REALIP_DEFAULT_REFRESH;
    conf->fetch_ipv6       = 1;
    conf->enabled          = 0;

    return conf;
}

static void *
merge_server_conf(apr_pool_t *p, void *base_conf, void *new_conf)
{
    cf_realip_server_conf *base = base_conf;
    cf_realip_server_conf *add  = new_conf;
    cf_realip_server_conf *conf = apr_pcalloc(p, sizeof(*conf));

    conf->source_url_v4    = add->source_url_v4 ? add->source_url_v4 : base->source_url_v4;
    conf->source_url_v6    = add->source_url_v6 ? add->source_url_v6 : base->source_url_v6;
    conf->output_path      = add->output_path   ? add->output_path   : base->output_path;
    conf->refresh_interval = add->refresh_interval > 0 ? add->refresh_interval : base->refresh_interval;
    conf->fetch_ipv6       = add->fetch_ipv6;
    conf->enabled          = add->enabled || base->enabled;

    return conf;
}

/* ----------------------------------------------------------------
 * Directive handlers
 * ---------------------------------------------------------------- */

static const char *
set_enabled(cmd_parms *cmd, void *dummy, int flag)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(cmd->server->module_config, &cf_realip_module);
    conf->enabled = flag;
    return NULL;
}

static const char *
set_source_url(cmd_parms *cmd, void *dummy, const char *url)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(cmd->server->module_config, &cf_realip_module);
    conf->source_url_v4 = apr_pstrdup(cmd->pool, url);
    return NULL;
}

static const char *
set_source_url_v6(cmd_parms *cmd, void *dummy, const char *url)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(cmd->server->module_config, &cf_realip_module);
    conf->source_url_v6 = apr_pstrdup(cmd->pool, url);
    return NULL;
}

static const char *
set_refresh_interval(cmd_parms *cmd, void *dummy, const char *val)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(cmd->server->module_config, &cf_realip_module);
    int interval = atoi(val);

    if (interval < CF_REALIP_MIN_REFRESH) {
        return apr_psprintf(cmd->pool,
            "CfRemoteipRefreshInterval must be >= %d seconds",
            CF_REALIP_MIN_REFRESH);
    }

    conf->refresh_interval = interval;
    return NULL;
}

static const char *
set_output_path(cmd_parms *cmd, void *dummy, const char *path)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(cmd->server->module_config, &cf_realip_module);

    if (path[0] != '/') {
        return "CfRemoteipOutputPath must be an absolute path";
    }

    conf->output_path = apr_pstrdup(cmd->pool, path);
    return NULL;
}

static const char *
set_fetch_ipv6(cmd_parms *cmd, void *dummy, int flag)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(cmd->server->module_config, &cf_realip_module);
    conf->fetch_ipv6 = flag;
    return NULL;
}

/* ----------------------------------------------------------------
 * Background update thread
 * ---------------------------------------------------------------- */

static void * APR_THREAD_FUNC
update_thread_func(apr_thread_t *thread, void *data)
{
    cf_realip_server_conf *conf = data;
    int result;

    /* Initial delay before first fetch */
    apr_sleep(apr_time_from_sec(2));

    while (!shutdown_flag) {
        result = cf_realip_fetch_and_write(
            conf->source_url_v4,
            conf->source_url_v6,
            conf->output_path,
            conf->fetch_ipv6
        );

        if (result == 1) {
            ap_log_error(APLOG_MARK, APLOG_NOTICE, 0, NULL,
                "cf_realip: config updated -> %s", conf->output_path);
        } else if (result == 0) {
            ap_log_error(APLOG_MARK, APLOG_DEBUG, 0, NULL,
                "cf_realip: IP list unchanged");
        } else {
            ap_log_error(APLOG_MARK, APLOG_ERR, 0, NULL,
                "cf_realip: update failed (failures=%u)",
                cf_realip_failure_count());
        }

        /* Sleep for the configured interval */
        for (int i = 0; i < conf->refresh_interval && !shutdown_flag; i++) {
            apr_sleep(apr_time_from_sec(1));
        }
    }

    return NULL;
}

/* ----------------------------------------------------------------
 * Hooks
 * ---------------------------------------------------------------- */

static int
post_config(apr_pool_t *pconf, apr_pool_t *plog, apr_pool_t *ptemp, server_rec *s)
{
    cf_realip_server_conf *conf =
        ap_get_module_config(s->module_config, &cf_realip_module);

    if (!conf->enabled) {
        return OK;
    }

    /* Avoid double-init during Apache's two-pass config loading */
    void *data = NULL;
    const char *key = "cf_realip_post_config";
    apr_pool_userdata_get(&data, key, s->process->pool);
    if (data == NULL) {
        apr_pool_userdata_set((void *)1, key, apr_pool_cleanup_null, s->process->pool);
        return OK;
    }

    ap_log_error(APLOG_MARK, APLOG_NOTICE, 0, s,
        "cf_realip v%s: starting (refresh=%ds, ipv6=%s, output=%s)",
        cf_realip_version(),
        conf->refresh_interval,
        conf->fetch_ipv6 ? "on" : "off",
        conf->output_path);

    cf_realip_reset_state();
    shutdown_flag = 0;

    apr_status_t rv = apr_thread_create(&update_thread, NULL,
        update_thread_func, conf, pconf);
    if (rv != APR_SUCCESS) {
        ap_log_error(APLOG_MARK, APLOG_ERR, rv, s,
            "cf_realip: failed to create update thread");
        return HTTP_INTERNAL_SERVER_ERROR;
    }

    return OK;
}

static apr_status_t
child_cleanup(void *data)
{
    shutdown_flag = 1;
    if (update_thread) {
        apr_status_t rv;
        apr_thread_join(&rv, update_thread);
        update_thread = NULL;
    }
    return APR_SUCCESS;
}

static void
child_init(apr_pool_t *p, server_rec *s)
{
    apr_pool_cleanup_register(p, NULL, child_cleanup, apr_pool_cleanup_null);
}

/* ----------------------------------------------------------------
 * Module definition
 * ---------------------------------------------------------------- */

static const command_rec directives[] = {
    AP_INIT_FLAG("CfRemoteipEnabled", set_enabled, NULL, RSRC_CONF,
        "Enable Cloudflare IP auto-fetching (on|off)"),
    AP_INIT_TAKE1("CfRemoteipSourceUrl", set_source_url, NULL, RSRC_CONF,
        "IPv4 list URL (default: Cloudflare official)"),
    AP_INIT_TAKE1("CfRemoteipSourceUrlV6", set_source_url_v6, NULL, RSRC_CONF,
        "IPv6 list URL (default: Cloudflare official)"),
    AP_INIT_TAKE1("CfRemoteipRefreshInterval", set_refresh_interval, NULL, RSRC_CONF,
        "Refresh interval in seconds (default: 3600, min: 300)"),
    AP_INIT_TAKE1("CfRemoteipOutputPath", set_output_path, NULL, RSRC_CONF,
        "Output path for RemoteIPTrustedProxy config"),
    AP_INIT_FLAG("CfRemoteipFetchIpv6", set_fetch_ipv6, NULL, RSRC_CONF,
        "Also fetch IPv6 ranges (on|off, default: on)"),
    { NULL }
};

static void
register_hooks(apr_pool_t *p)
{
    ap_hook_post_config(post_config, NULL, NULL, APR_HOOK_MIDDLE);
    ap_hook_child_init(child_init, NULL, NULL, APR_HOOK_MIDDLE);
}

AP_DECLARE_MODULE(cf_realip) = {
    STANDARD20_MODULE_STUFF,
    NULL,                   /* create per-directory config */
    NULL,                   /* merge per-directory config */
    create_server_conf,     /* create per-server config */
    merge_server_conf,      /* merge per-server config */
    directives,             /* directive table */
    register_hooks          /* register hooks */
};
