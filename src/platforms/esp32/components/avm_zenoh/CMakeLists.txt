# COMPONENT_DIR is set by ESP-IDF to the component's actual source directory
# before including this file — safe to use even in the requirements phase.
# CMAKE_CURRENT_SOURCE_DIR and CMAKE_SOURCE_DIR both resolve to the build tree
# during that phase, so they cannot be used here.
set(ZENOH_PICO_DIR "${COMPONENT_DIR}/../../third_party/zenoh-pico")

if (NOT EXISTS "${ZENOH_PICO_DIR}/include/zenoh-pico.h")
    message(FATAL_ERROR "zenoh-pico not found at ${ZENOH_PICO_DIR}. "
        "Run: git submodule update --init src/platforms/esp32/third_party/zenoh-pico")
endif()

# Core zenoh-pico sources (platform-agnostic)
file(GLOB_RECURSE ZENOH_CORE_SRCS
    "${ZENOH_PICO_DIR}/src/api/*.c"
    "${ZENOH_PICO_DIR}/src/collections/*.c"
    "${ZENOH_PICO_DIR}/src/link/*.c"
    "${ZENOH_PICO_DIR}/src/net/*.c"
    "${ZENOH_PICO_DIR}/src/protocol/*.c"
    "${ZENOH_PICO_DIR}/src/runtime/*.c"
    "${ZENOH_PICO_DIR}/src/session/*.c"
    "${ZENOH_PICO_DIR}/src/transport/*.c"
    "${ZENOH_PICO_DIR}/src/utils/*.c"
)

# Exclude most raweth transport files (requires raw ethernet hardware).
# transport/raweth/link.c is kept because it provides stub implementations of
# _z_endpoint_raweth_valid, _z_new_link_raweth, _z_raweth_config_from_strn, etc.
# that endpoint.c and link.c call unconditionally regardless of Z_FEATURE_RAWETH_TRANSPORT.
# Exclude raweth transport (requires raw Ethernet hardware).
# transport/raweth/link.c is kept because it has a proper #else stub block for the
# _z_endpoint_raweth_valid / _z_new_link_raweth / _z_raweth_config_from_strn symbols.
# For _z_raweth_send_* (tx.c has no #else block), raweth_stubs.c provides the stubs.
list(FILTER ZENOH_CORE_SRCS EXCLUDE REGEX ".*/raweth/.*")
list(APPEND ZENOH_CORE_SRCS "${ZENOH_PICO_DIR}/src/transport/raweth/link.c")

# ESP-IDF system backend (uses esp_random, esp_heap_caps, LwIP sockets).
# freertos/system.c is incompatible with ESP-IDF's SMP FreeRTOS (taskENTER_CRITICAL
# requires a spinlock argument in ESP-IDF Xtensa port).
set(ZENOH_SYS_SRCS
    "${ZENOH_PICO_DIR}/src/system/espidf/system.c"
    "${ZENOH_PICO_DIR}/src/system/espidf/network.c"
    "${ZENOH_PICO_DIR}/src/system/common/platform.c"
    "${ZENOH_PICO_DIR}/src/system/common/serial.c"
)

if (IDF_VERSION_MAJOR GREATER_EQUAL 5)
    set(OPTIONAL_WHOLE_ARCHIVE WHOLE_ARCHIVE)
else()
    set(OPTIONAL_WHOLE_ARCHIVE "")
endif()

idf_component_register(
    SRCS "zenoh_nif.c" "raweth_stubs.c" ${ZENOH_CORE_SRCS} ${ZENOH_SYS_SRCS}
    INCLUDE_DIRS "${ZENOH_PICO_DIR}/include" "${COMPONENT_DIR}/zenoh_config"
    PRIV_REQUIRES "libatomvm" "avm_sys" "esp_system" "driver" "lwip"
    ${OPTIONAL_WHOLE_ARCHIVE}
)

# ZENOH_ESPIDF: use ESP-IDF system backend (pthreads, LwIP sockets, esp_random).
# ZENOH_GENERIC: replace default config.h with zenoh_config/zenoh_generic_config.h,
# which disables UDP multicast and IPv6 (not available in ESP-IDF LwIP by default).
target_compile_definitions(${COMPONENT_LIB} PRIVATE
    ZENOH_ESPIDF=1
    ZENOH_GENERIC=1
)
