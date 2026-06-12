// SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
// Copyright 2024 AtomVM Contributors

#include <sdkconfig.h>
#ifdef CONFIG_AVM_ENABLE_ZENOH_NIFS

#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <string.h>
#include <zenoh-pico.h>

#include "context.h"
#include "defaultatoms.h"
#include "erl_nif.h"
#include "erl_nif_priv.h"
#include "interop.h"
#include "memory.h"
#include "nifs.h"
#include "portnifloader.h"
#include "term.h"

#define ZENOH_KEYEXPR_MAX 256
#define ZENOH_PAYLOAD_MAX 4096
#define ZENOH_QUEUE_DEPTH 16

typedef struct {
    char keyexpr[ZENOH_KEYEXPR_MAX];
    size_t keyexpr_len;
    uint8_t payload[ZENOH_PAYLOAD_MAX];
    size_t payload_len;
} ZenohMessage;

typedef struct {
    z_owned_session_t session;
    bool is_open;
} ZenohSessionResource;

typedef struct {
    z_owned_publisher_t publisher;
    bool is_valid;
} ZenohPublisherResource;

typedef struct {
    z_owned_subscriber_t subscriber;
    QueueHandle_t queue;
    bool is_valid;
} ZenohSubscriberResource;

static ErlNifResourceType *zenoh_session_resource_type;
static ErlNifResourceType *zenoh_publisher_resource_type;
static ErlNifResourceType *zenoh_subscriber_resource_type;

static void zenoh_session_dtor(ErlNifEnv *env, void *obj)
{
    UNUSED(env);
    ZenohSessionResource *res = (ZenohSessionResource *) obj;
    if (res->is_open) {
        zp_stop_read_task(z_loan_mut(res->session));
        zp_stop_lease_task(z_loan_mut(res->session));
        z_close(z_loan_mut(res->session), NULL);
        res->is_open = false;
    }
}

static void zenoh_publisher_dtor(ErlNifEnv *env, void *obj)
{
    UNUSED(env);
    ZenohPublisherResource *res = (ZenohPublisherResource *) obj;
    if (res->is_valid) {
        z_undeclare_publisher(z_move(res->publisher));
        res->is_valid = false;
    }
}

static void zenoh_subscriber_dtor(ErlNifEnv *env, void *obj)
{
    UNUSED(env);
    ZenohSubscriberResource *res = (ZenohSubscriberResource *) obj;
    if (res->is_valid) {
        z_undeclare_subscriber(z_move(res->subscriber));
        res->is_valid = false;
    }
    if (res->queue != NULL) {
        vQueueDelete(res->queue);
        res->queue = NULL;
    }
}

static const ErlNifResourceTypeInit ZenohSessionResourceTypeInit = {
    .members = 1,
    .dtor = zenoh_session_dtor,
};

static const ErlNifResourceTypeInit ZenohPublisherResourceTypeInit = {
    .members = 1,
    .dtor = zenoh_publisher_dtor,
};

static const ErlNifResourceTypeInit ZenohSubscriberResourceTypeInit = {
    .members = 1,
    .dtor = zenoh_subscriber_dtor,
};

static void zenoh_nif_init(GlobalContext *global)
{
    ErlNifEnv env;
    erl_nif_env_partial_init_from_globalcontext(&env, global);
    zenoh_session_resource_type = enif_init_resource_type(
        &env, "zenoh_session", &ZenohSessionResourceTypeInit, ERL_NIF_RT_CREATE, NULL);
    zenoh_publisher_resource_type = enif_init_resource_type(
        &env, "zenoh_publisher", &ZenohPublisherResourceTypeInit, ERL_NIF_RT_CREATE, NULL);
    zenoh_subscriber_resource_type = enif_init_resource_type(
        &env, "zenoh_subscriber", &ZenohSubscriberResourceTypeInit, ERL_NIF_RT_CREATE, NULL);
}

static void zenoh_sub_callback(z_loaned_sample_t *sample, void *arg)
{
    QueueHandle_t queue = (QueueHandle_t) arg;
    ZenohMessage msg;
    memset(&msg, 0, sizeof(msg));

    // Extract keyexpr string
    z_view_string_t keystr;
    z_keyexpr_as_view_string(z_sample_keyexpr(sample), &keystr);
    const z_loaned_string_t *ke_loaned = z_view_string_loan(&keystr);
    size_t ke_len = z_string_len(ke_loaned);
    if (ke_len >= ZENOH_KEYEXPR_MAX) {
        ke_len = ZENOH_KEYEXPR_MAX - 1;
    }
    memcpy(msg.keyexpr, z_string_data(ke_loaned), ke_len);
    msg.keyexpr_len = ke_len;

    // Extract payload bytes
    const z_loaned_bytes_t *payload_bytes = z_sample_payload(sample);
    z_bytes_reader_t reader = z_bytes_get_reader(payload_bytes);
    size_t payload_len = z_bytes_reader_remaining(&reader);
    if (payload_len > ZENOH_PAYLOAD_MAX) {
        payload_len = ZENOH_PAYLOAD_MAX;
    }
    z_bytes_reader_read(&reader, msg.payload, payload_len);
    msg.payload_len = payload_len;

    xQueueSend(queue, &msg, 0);
}

// zenoh:open/1 :: binary() -> {ok, session()} | {error, atom()}
// Arg: endpoint e.g. <<"tcp/192.168.1.1:7447">>
static term nif_zenoh_open(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    VALIDATE_VALUE(argv[0], term_is_binary);

    char *endpoint = interop_binary_to_string(argv[0]);
    if (IS_NULL_PTR(endpoint)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }

    z_owned_config_t config;
    z_config_default(&config);
    zp_config_insert(z_loan_mut(config), Z_CONFIG_MODE_KEY, "client");
    if (zp_config_insert(z_loan_mut(config), Z_CONFIG_CONNECT_KEY, endpoint) < 0) {
        free(endpoint);
        z_drop(z_move(config));
        RAISE_ERROR(BADARG_ATOM);
    }
    free(endpoint);

    ZenohSessionResource *res = enif_alloc_resource(zenoh_session_resource_type, sizeof(ZenohSessionResource));
    if (IS_NULL_PTR(res)) {
        z_drop(z_move(config));
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    res->is_open = false;

    if (z_open(&res->session, z_move(config), NULL) < 0) {
        enif_release_resource(res);
        RAISE_ERROR(globalcontext_make_atom(ctx->global, ATOM_STR("\xB", "zenoh_error")));
    }
    zp_start_read_task(z_loan_mut(res->session), NULL);
    zp_start_lease_task(z_loan_mut(res->session), NULL);
    res->is_open = true;

    if (UNLIKELY(memory_ensure_free(ctx, TERM_BOXED_RESOURCE_SIZE) != MEMORY_GC_OK)) {
        zenoh_session_dtor(NULL, res);
        enif_release_resource(res);
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term obj = term_from_resource(res, &ctx->heap);
    enif_release_resource(res);

    if (UNLIKELY(memory_ensure_free_with_roots(ctx, TUPLE_SIZE(2), 1, &obj, MEMORY_CAN_SHRINK) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term result = term_alloc_tuple(2, &ctx->heap);
    term_put_tuple_element(result, 0, OK_ATOM);
    term_put_tuple_element(result, 1, obj);
    return result;
}

// zenoh:close/1 :: session() -> ok
static term nif_zenoh_close(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *res_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_session_resource_type, &res_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohSessionResource *res = (ZenohSessionResource *) res_obj;
    if (res->is_open) {
        zp_stop_read_task(z_loan_mut(res->session));
        zp_stop_lease_task(z_loan_mut(res->session));
        z_close(z_loan_mut(res->session), NULL);
        res->is_open = false;
    }
    return OK_ATOM;
}

// zenoh:put/3 :: session(), binary(), binary() -> ok | {error, atom()}
static term nif_zenoh_put(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *res_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_session_resource_type, &res_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohSessionResource *res = (ZenohSessionResource *) res_obj;
    if (!res->is_open) {
        RAISE_ERROR(BADARG_ATOM);
    }

    VALIDATE_VALUE(argv[1], term_is_binary);
    VALIDATE_VALUE(argv[2], term_is_binary);

    char *keyexpr_str = interop_binary_to_string(argv[1]);
    if (IS_NULL_PTR(keyexpr_str)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }

    z_view_keyexpr_t ke;
    if (z_view_keyexpr_from_str(&ke, keyexpr_str) < 0) {
        free(keyexpr_str);
        RAISE_ERROR(BADARG_ATOM);
    }

    size_t payload_len = term_binary_size(argv[2]);
    const uint8_t *payload_data = (const uint8_t *) term_binary_data(argv[2]);

    z_owned_bytes_t payload;
    z_bytes_copy_from_buf(&payload, payload_data, payload_len);

    int rc = z_put(z_loan(res->session), z_loan(ke), z_move(payload), NULL);
    free(keyexpr_str);

    if (rc < 0) {
        RAISE_ERROR(globalcontext_make_atom(ctx->global, ATOM_STR("\xB", "zenoh_error")));
    }
    return OK_ATOM;
}

// zenoh:declare_publisher/2 :: session(), binary() -> {ok, publisher()} | {error, atom()}
static term nif_zenoh_declare_publisher(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *sess_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_session_resource_type, &sess_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohSessionResource *sess = (ZenohSessionResource *) sess_obj;
    if (!sess->is_open) {
        RAISE_ERROR(BADARG_ATOM);
    }

    VALIDATE_VALUE(argv[1], term_is_binary);
    char *keyexpr_str = interop_binary_to_string(argv[1]);
    if (IS_NULL_PTR(keyexpr_str)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }

    z_view_keyexpr_t ke;
    if (z_view_keyexpr_from_str(&ke, keyexpr_str) < 0) {
        free(keyexpr_str);
        RAISE_ERROR(BADARG_ATOM);
    }

    ZenohPublisherResource *res = enif_alloc_resource(zenoh_publisher_resource_type, sizeof(ZenohPublisherResource));
    if (IS_NULL_PTR(res)) {
        free(keyexpr_str);
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    res->is_valid = false;

    // Note: session arg first, then output pointer (zenoh-pico 1.9.0 API)
    if (z_declare_publisher(z_loan(sess->session), &res->publisher, z_loan(ke), NULL) < 0) {
        free(keyexpr_str);
        enif_release_resource(res);
        RAISE_ERROR(globalcontext_make_atom(ctx->global, ATOM_STR("\xB", "zenoh_error")));
    }
    free(keyexpr_str);
    res->is_valid = true;

    if (UNLIKELY(memory_ensure_free(ctx, TERM_BOXED_RESOURCE_SIZE) != MEMORY_GC_OK)) {
        zenoh_publisher_dtor(NULL, res);
        enif_release_resource(res);
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term obj = term_from_resource(res, &ctx->heap);
    enif_release_resource(res);

    if (UNLIKELY(memory_ensure_free_with_roots(ctx, TUPLE_SIZE(2), 1, &obj, MEMORY_CAN_SHRINK) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term result = term_alloc_tuple(2, &ctx->heap);
    term_put_tuple_element(result, 0, OK_ATOM);
    term_put_tuple_element(result, 1, obj);
    return result;
}

// zenoh:publisher_put/2 :: publisher(), binary() -> ok | {error, atom()}
static term nif_zenoh_publisher_put(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *res_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_publisher_resource_type, &res_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohPublisherResource *res = (ZenohPublisherResource *) res_obj;
    if (!res->is_valid) {
        RAISE_ERROR(BADARG_ATOM);
    }

    VALIDATE_VALUE(argv[1], term_is_binary);
    size_t payload_len = term_binary_size(argv[1]);
    const uint8_t *payload_data = (const uint8_t *) term_binary_data(argv[1]);

    z_owned_bytes_t payload;
    z_bytes_copy_from_buf(&payload, payload_data, payload_len);

    if (z_publisher_put(z_loan(res->publisher), z_move(payload), NULL) < 0) {
        RAISE_ERROR(globalcontext_make_atom(ctx->global, ATOM_STR("\xB", "zenoh_error")));
    }
    return OK_ATOM;
}

// zenoh:undeclare_publisher/1 :: publisher() -> ok
static term nif_zenoh_undeclare_publisher(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *res_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_publisher_resource_type, &res_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohPublisherResource *res = (ZenohPublisherResource *) res_obj;
    if (res->is_valid) {
        z_undeclare_publisher(z_move(res->publisher));
        res->is_valid = false;
    }
    return OK_ATOM;
}

// zenoh:declare_subscriber/2 :: session(), binary() -> {ok, subscriber()} | {error, atom()}
static term nif_zenoh_declare_subscriber(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *sess_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_session_resource_type, &sess_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohSessionResource *sess = (ZenohSessionResource *) sess_obj;
    if (!sess->is_open) {
        RAISE_ERROR(BADARG_ATOM);
    }

    VALIDATE_VALUE(argv[1], term_is_binary);
    char *keyexpr_str = interop_binary_to_string(argv[1]);
    if (IS_NULL_PTR(keyexpr_str)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }

    z_view_keyexpr_t ke;
    if (z_view_keyexpr_from_str(&ke, keyexpr_str) < 0) {
        free(keyexpr_str);
        RAISE_ERROR(BADARG_ATOM);
    }

    QueueHandle_t queue = xQueueCreate(ZENOH_QUEUE_DEPTH, sizeof(ZenohMessage));
    if (queue == NULL) {
        free(keyexpr_str);
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }

    ZenohSubscriberResource *res = enif_alloc_resource(zenoh_subscriber_resource_type, sizeof(ZenohSubscriberResource));
    if (IS_NULL_PTR(res)) {
        free(keyexpr_str);
        vQueueDelete(queue);
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    res->queue = queue;
    res->is_valid = false;

    z_owned_closure_sample_t closure;
    z_closure_sample(&closure, zenoh_sub_callback, NULL, (void *) queue);

    // Note: session arg first, then output pointer (zenoh-pico 1.9.0 API)
    if (z_declare_subscriber(z_loan(sess->session), &res->subscriber, z_loan(ke), z_move(closure), NULL) < 0) {
        free(keyexpr_str);
        vQueueDelete(queue);
        enif_release_resource(res);
        RAISE_ERROR(globalcontext_make_atom(ctx->global, ATOM_STR("\xB", "zenoh_error")));
    }
    free(keyexpr_str);
    res->is_valid = true;

    if (UNLIKELY(memory_ensure_free(ctx, TERM_BOXED_RESOURCE_SIZE) != MEMORY_GC_OK)) {
        zenoh_subscriber_dtor(NULL, res);
        enif_release_resource(res);
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term obj = term_from_resource(res, &ctx->heap);
    enif_release_resource(res);

    if (UNLIKELY(memory_ensure_free_with_roots(ctx, TUPLE_SIZE(2), 1, &obj, MEMORY_CAN_SHRINK) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }
    term result = term_alloc_tuple(2, &ctx->heap);
    term_put_tuple_element(result, 0, OK_ATOM);
    term_put_tuple_element(result, 1, obj);
    return result;
}

// zenoh:subscriber_recv/2 :: subscriber(), integer() -> {ok, binary(), binary()} | timeout | {error, atom()}
// timeout_ms: ms to wait, -1 = block forever
static term nif_zenoh_subscriber_recv(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *res_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_subscriber_resource_type, &res_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohSubscriberResource *res = (ZenohSubscriberResource *) res_obj;
    if (!res->is_valid || res->queue == NULL) {
        RAISE_ERROR(BADARG_ATOM);
    }

    VALIDATE_VALUE(argv[1], term_is_integer);
    int32_t timeout_ms = term_to_int32(argv[1]);
    TickType_t ticks = (timeout_ms < 0) ? portMAX_DELAY : pdMS_TO_TICKS(timeout_ms);

    ZenohMessage msg;
    if (xQueueReceive(res->queue, &msg, ticks) != pdTRUE) {
        return globalcontext_make_atom(ctx->global, ATOM_STR("\x7", "timeout"));
    }

    size_t heap_needed = TUPLE_SIZE(3)
        + term_binary_heap_size(msg.keyexpr_len)
        + term_binary_heap_size(msg.payload_len);

    if (UNLIKELY(memory_ensure_free(ctx, heap_needed) != MEMORY_GC_OK)) {
        RAISE_ERROR(OUT_OF_MEMORY_ATOM);
    }

    term ke_bin = term_from_literal_binary(msg.keyexpr, msg.keyexpr_len, &ctx->heap, ctx->global);
    term payload_bin = term_from_literal_binary(msg.payload, msg.payload_len, &ctx->heap, ctx->global);

    term result = term_alloc_tuple(3, &ctx->heap);
    term_put_tuple_element(result, 0, OK_ATOM);
    term_put_tuple_element(result, 1, ke_bin);
    term_put_tuple_element(result, 2, payload_bin);
    return result;
}

// zenoh:undeclare_subscriber/1 :: subscriber() -> ok
static term nif_zenoh_undeclare_subscriber(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    void *res_obj = NULL;
    if (UNLIKELY(!enif_get_resource(erl_nif_env_from_context(ctx), argv[0], zenoh_subscriber_resource_type, &res_obj))) {
        RAISE_ERROR(BADARG_ATOM);
    }
    ZenohSubscriberResource *res = (ZenohSubscriberResource *) res_obj;
    if (res->is_valid) {
        z_undeclare_subscriber(z_move(res->subscriber));
        res->is_valid = false;
    }
    return OK_ATOM;
}

static const struct Nif zenoh_open_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_open };
static const struct Nif zenoh_close_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_close };
static const struct Nif zenoh_put_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_put };
static const struct Nif zenoh_declare_publisher_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_declare_publisher };
static const struct Nif zenoh_publisher_put_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_publisher_put };
static const struct Nif zenoh_undeclare_publisher_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_undeclare_publisher };
static const struct Nif zenoh_declare_subscriber_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_declare_subscriber };
static const struct Nif zenoh_subscriber_recv_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_subscriber_recv };
static const struct Nif zenoh_undeclare_subscriber_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_zenoh_undeclare_subscriber };

static const struct Nif *zenoh_nif_get_nif(const char *nifname)
{
    if (strcmp("zenoh:open/1", nifname) == 0) return &zenoh_open_nif;
    if (strcmp("zenoh:close/1", nifname) == 0) return &zenoh_close_nif;
    if (strcmp("zenoh:put/3", nifname) == 0) return &zenoh_put_nif;
    if (strcmp("zenoh:declare_publisher/2", nifname) == 0) return &zenoh_declare_publisher_nif;
    if (strcmp("zenoh:publisher_put/2", nifname) == 0) return &zenoh_publisher_put_nif;
    if (strcmp("zenoh:undeclare_publisher/1", nifname) == 0) return &zenoh_undeclare_publisher_nif;
    if (strcmp("zenoh:declare_subscriber/2", nifname) == 0) return &zenoh_declare_subscriber_nif;
    if (strcmp("zenoh:subscriber_recv/2", nifname) == 0) return &zenoh_subscriber_recv_nif;
    if (strcmp("zenoh:undeclare_subscriber/1", nifname) == 0) return &zenoh_undeclare_subscriber_nif;
    return NULL;
}

REGISTER_NIF_COLLECTION(zenoh, zenoh_nif_init, NULL, zenoh_nif_get_nif)

#endif /* CONFIG_AVM_ENABLE_ZENOH_NIFS */
