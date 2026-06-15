# COMPONENT_DIR is set by ESP-IDF to the component's actual source directory
# before including this file — safe to use even in the requirements phase.
# CMAKE_CURRENT_SOURCE_DIR and CMAKE_SOURCE_DIR both resolve to the build tree
# during that phase, so they cannot be used here.
set(ZENOH_PICO_DIR "${COMPONENT_DIR}/../../third_party/zenoh-pico")

if (NOT EXISTS "${ZENOH_PICO_DIR}/include/zenoh-pico.h")
    message(FATAL_ERROR "zenoh-pico not found at ${ZENOH_PICO_DIR}. "
        "Run: git submodule update --init src/platforms/esp32/third_party/zenoh-pico")
endif()

# Generate config.h from config.h.in (not shipped in the source tree).
# ZP_SYSTEM_PLATFORM_HEADER is left unset so the #cmakedefine becomes /* #undef */.
# The ZENOH_GENERIC compile definition makes the generated #else block unreachable,
# so the unresolved @VAR@ tokens in that branch do not matter.
configure_file(
    "${ZENOH_PICO_DIR}/include/zenoh-pico/config.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/zenoh_pico_include/zenoh-pico/config.h"
    @ONLY
)

# Core zenoh-pico sources (platform-agnostic), mirroring zenoh-pico's own CMakeLists.txt.
file(GLOB_RECURSE ZENOH_CORE_SRCS
    "${ZENOH_PICO_DIR}/src/api/*.c"
    "${ZENOH_PICO_DIR}/src/collections/*.c"
    "${ZENOH_PICO_DIR}/src/net/*.c"
    "${ZENOH_PICO_DIR}/src/protocol/*.c"
    "${ZENOH_PICO_DIR}/src/runtime/*.c"
    "${ZENOH_PICO_DIR}/src/session/*.c"
    "${ZENOH_PICO_DIR}/src/transport/*.c"
    "${ZENOH_PICO_DIR}/src/utils/*.c"
    "${ZENOH_PICO_DIR}/src/system/common/*.c"
)

# Link layer: use non-recursive GLOB to avoid pulling in platform-specific transport files.
file(GLOB ZENOH_LINK_SRCS
    "${ZENOH_PICO_DIR}/src/link/config/*.c"
    "${ZENOH_PICO_DIR}/src/link/multicast/*.c"
    "${ZENOH_PICO_DIR}/src/link/unicast/*.c"
    "${ZENOH_PICO_DIR}/src/link/transport/common/*.c"
)
list(APPEND ZENOH_CORE_SRCS ${ZENOH_LINK_SRCS})
list(APPEND ZENOH_CORE_SRCS
    "${ZENOH_PICO_DIR}/src/link/link.c"
    "${ZENOH_PICO_DIR}/src/link/endpoint.c"
    "${ZENOH_PICO_DIR}/src/link/transport/tcp/address.c"
    "${ZENOH_PICO_DIR}/src/link/transport/udp/address.c"
    "${ZENOH_PICO_DIR}/src/link/transport/upper/serial_protocol.c"
    "${ZENOH_PICO_DIR}/src/link/transport/upper/tls_stream.c"
)

# Exclude raweth transport (requires raw Ethernet hardware).
# transport/raweth/link.c is kept because it provides stubs for
# _z_endpoint_raweth_valid, _z_new_link_raweth, _z_raweth_config_from_strn.
# raweth_stubs.c provides stubs for tx.c functions that have no #else block.
list(FILTER ZENOH_CORE_SRCS EXCLUDE REGEX ".*/raweth/.*")
list(APPEND ZENOH_CORE_SRCS "${ZENOH_PICO_DIR}/src/transport/raweth/link.c")

# ESP-IDF system backend (uses esp_random, LwIP sockets, ESP-IDF UART).
set(ZENOH_SYS_SRCS
    "${ZENOH_PICO_DIR}/src/system/espidf/system.c"
    "${ZENOH_PICO_DIR}/src/system/socket/esp32.c"
    "${ZENOH_PICO_DIR}/src/link/transport/tcp/tcp_esp32.c"
    "${ZENOH_PICO_DIR}/src/link/transport/udp/udp_esp32.c"
    "${ZENOH_PICO_DIR}/src/link/transport/serial/uart_espidf.c"
)

if (IDF_VERSION_MAJOR GREATER_EQUAL 5)
    set(OPTIONAL_WHOLE_ARCHIVE WHOLE_ARCHIVE)
else()
    set(OPTIONAL_WHOLE_ARCHIVE "")
endif()

idf_component_register(
    SRCS "zenoh_nif.c" "raweth_stubs.c" ${ZENOH_CORE_SRCS} ${ZENOH_SYS_SRCS}
    INCLUDE_DIRS "${ZENOH_PICO_DIR}/include" "${COMPONENT_DIR}/zenoh_config" "${CMAKE_CURRENT_BINARY_DIR}/zenoh_pico_include"
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
