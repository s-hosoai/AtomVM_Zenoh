#
# This file is part of AtomVM.
#
# Copyright 2019 Riccardo Binetti <rbino@gmx.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
#

project(examples_elixir_esp32)

include(BuildElixir)

pack_runnable(Blink Blink estdlib eavmlib exavmlib avm_esp32)
pack_runnable(M5Blink M5Blink estdlib eavmlib exavmlib avm_esp32)
pack_runnable(Ledc_x4 Ledc_x4 estdlib eavmlib exavmlib avm_esp32)
if(NOT (AVM_DISABLE_FP))
    pack_runnable(SHT31 SHT31 estdlib eavmlib exavmlib avm_esp32)
endif()

# Zenoh examples share EspConfig (WiFi/Zenoh credentials).
# EspConfig.ex is gitignored — copy from EspConfig.ex.example and fill in values,
# then run: idf.py reconfigure && make ZenohPub ZenohSub
find_package(Elixir REQUIRED)

set(_zenoh_archives
    ${CMAKE_BINARY_DIR}/libs/estdlib/src/estdlib.avm
    ${CMAKE_BINARY_DIR}/libs/eavmlib/src/eavmlib.avm
    ${CMAKE_BINARY_DIR}/libs/exavmlib/lib/exavmlib.avm
    ${CMAKE_BINARY_DIR}/libs/avm_esp32/src/avm_esp32.avm
)

add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Elixir.EspConfig.beam
    COMMAND elixirc -o ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/EspConfig.ex
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/EspConfig.ex
    COMMENT "Compiling EspConfig.ex"
    VERBATIM
)

foreach(_zenoh_mod ZenohPub ZenohSub)
    add_custom_command(
        OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Elixir.${_zenoh_mod}.beam
        COMMAND elixirc -o ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/${_zenoh_mod}.ex
        DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${_zenoh_mod}.ex
        COMMENT "Compiling ${_zenoh_mod}.ex"
        VERBATIM
    )
    add_custom_command(
        OUTPUT ${_zenoh_mod}.avm
        DEPENDS
            ${CMAKE_CURRENT_BINARY_DIR}/Elixir.${_zenoh_mod}.beam
            ${CMAKE_CURRENT_BINARY_DIR}/Elixir.EspConfig.beam
            PackBEAM estdlib eavmlib exavmlib avm_esp32
        COMMAND ${CMAKE_BINARY_DIR}/tools/packbeam/packbeam create
                -s Elixir.${_zenoh_mod} ${_zenoh_mod}.avm
                ${CMAKE_CURRENT_BINARY_DIR}/Elixir.${_zenoh_mod}.beam
                ${CMAKE_CURRENT_BINARY_DIR}/Elixir.EspConfig.beam
                ${_zenoh_archives}
        COMMENT "Packing ${_zenoh_mod}.avm"
        VERBATIM
    )
    add_custom_target(${_zenoh_mod} ALL DEPENDS ${_zenoh_mod}.avm)
endforeach()

# ---- GiocciClient (two-stage: compile example first, then embed its BEAM) ----
#
# Stage 1: compile GiocciClientExample.ex → Elixir.GiocciClientExample.beam
# This BEAM file is NOT packed into the AVM; its bytes are embedded as a literal
# inside GiocciClient.beam and sent to the engine at runtime via save_module.
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Elixir.GiocciClientExample.beam
    COMMAND elixirc -o ${CMAKE_CURRENT_BINARY_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/GiocciClientExample.ex
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/GiocciClientExample.ex
    COMMENT "Compiling GiocciClientExample.ex"
    VERBATIM
)

# Stage 2: compile GiocciClient.ex with GIOCCI_EXAMPLE_BEAM_DIR pointing to the
# binary dir so that File.read!("Elixir.GiocciClientExample.beam") succeeds.
add_custom_command(
    OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/Elixir.GiocciClient.beam
    COMMAND ${CMAKE_COMMAND} -E env
            GIOCCI_EXAMPLE_BEAM_DIR=${CMAKE_CURRENT_BINARY_DIR}
            elixirc -o ${CMAKE_CURRENT_BINARY_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/GiocciClient.ex
    DEPENDS
        ${CMAKE_CURRENT_SOURCE_DIR}/GiocciClient.ex
        ${CMAKE_CURRENT_BINARY_DIR}/Elixir.GiocciClientExample.beam
    COMMENT "Compiling GiocciClient.ex (embeds GiocciClientExample.beam)"
    VERBATIM
)

add_custom_command(
    OUTPUT GiocciClient.avm
    DEPENDS
        ${CMAKE_CURRENT_BINARY_DIR}/Elixir.GiocciClient.beam
        ${CMAKE_CURRENT_BINARY_DIR}/Elixir.EspConfig.beam
        PackBEAM estdlib eavmlib exavmlib avm_esp32
    COMMAND ${CMAKE_BINARY_DIR}/tools/packbeam/packbeam create
            -s Elixir.GiocciClient GiocciClient.avm
            ${CMAKE_CURRENT_BINARY_DIR}/Elixir.GiocciClient.beam
            ${CMAKE_CURRENT_BINARY_DIR}/Elixir.EspConfig.beam
            ${_zenoh_archives}
    COMMENT "Packing GiocciClient.avm"
    VERBATIM
)
add_custom_target(GiocciClient ALL DEPENDS GiocciClient.avm)
