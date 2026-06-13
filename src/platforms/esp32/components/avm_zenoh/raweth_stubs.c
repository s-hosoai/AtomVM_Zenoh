// Stub implementations for raweth transport functions when Z_FEATURE_RAWETH_TRANSPORT=0.
// These symbols are referenced unconditionally by transport/common/tx.c and
// transport/multicast/transport.c regardless of the raweth feature flag.
#include "zenoh-pico/transport/raweth/tx.h"
#include "zenoh-pico/utils/result.h"

#if Z_FEATURE_RAWETH_TRANSPORT != 1

z_result_t _z_raweth_link_send_t_msg(const _z_link_t *zl, const _z_transport_message_t *t_msg) {
    (void)zl;
    (void)t_msg;
    return _Z_ERR_TRANSPORT_NOT_AVAILABLE;
}

z_result_t _z_raweth_send_t_msg(_z_transport_common_t *ztc, const _z_transport_message_t *t_msg) {
    (void)ztc;
    (void)t_msg;
    return _Z_ERR_TRANSPORT_NOT_AVAILABLE;
}

z_result_t _z_raweth_send_n_msg(_z_session_t *zn, const _z_network_message_t *z_msg, z_reliability_t reliability,
                                z_congestion_control_t cong_ctrl) {
    (void)zn;
    (void)z_msg;
    (void)reliability;
    (void)cong_ctrl;
    return _Z_ERR_TRANSPORT_NOT_AVAILABLE;
}

#endif
