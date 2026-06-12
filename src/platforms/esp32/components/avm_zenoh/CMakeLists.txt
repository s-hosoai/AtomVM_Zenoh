# CMAKE_SOURCE_DIR is the ESP-IDF project root (src/platforms/esp32/).
# CMAKE_CURRENT_SOURCE_DIR may resolve through the build tree in the requirements
# phase, so we anchor from the project root instead.
set(ZENOH_PICO_DIR "${CMAKE_SOURCE_DIR}/third_party/zenoh-pico")

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

# Exclude raweth transport (requires raw ethernet hardware)
list(FILTER ZENOH_CORE_SRCS EXCLUDE REGEX ".*/raweth/.*")

# ESP-IDF specific system backend
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
    SRCS "zenoh_nif.c" ${ZENOH_CORE_SRCS} ${ZENOH_SYS_SRCS}
    INCLUDE_DIRS "${ZENOH_PICO_DIR}/include"
    PRIV_REQUIRES "libatomvm" "avm_sys" "esp_system" "pthread" "lwip"
    ${OPTIONAL_WHOLE_ARCHIVE}
)

# ZENOH_ESPIDF: use ESP-IDF system backend (FreeRTOS tasks + LwIP sockets)
target_compile_definitions(${COMPONENT_LIB} PRIVATE ZENOH_ESPIDF=1)
