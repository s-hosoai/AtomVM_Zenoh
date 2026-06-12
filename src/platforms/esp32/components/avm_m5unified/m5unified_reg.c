/*
 * SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
 */

#include <sdkconfig.h>
#ifdef CONFIG_AVM_ENABLE_M5UNIFIED_NIFS

#include <string.h>

#include "context.h"
#include "defaultatoms.h"
#include "exportedfunction.h"
#include "interop.h"
#include "nifs.h"
#include "portnifloader.h"
#include "term.h"

//#define ENABLE_TRACE
#include "trace.h"

extern void atomvm_m5_begin(void);
extern void atomvm_m5_update(void);
extern void atomvm_m5_display_print(const char *text);
extern void atomvm_m5_display_println(const char *text);
extern void atomvm_m5_display_fill_screen(unsigned int color);
extern void atomvm_m5_display_set_cursor(int x, int y);
extern void atomvm_m5_display_set_text_size(int size);
extern void atomvm_m5_display_set_text_color(unsigned int color);
extern int atomvm_m5_btn_a_is_pressed(void);

static term nif_m5_begin(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);
    atomvm_m5_begin();
    return OK_ATOM;
}

static term nif_m5_update(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);
    atomvm_m5_update();
    return OK_ATOM;
}

static term nif_m5_display_print(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (!term_is_binary(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    char *str = interop_binary_to_string(argv[0]);
    if (!str) {
        RAISE_ERROR(BADARG_ATOM);
    }
    atomvm_m5_display_print(str);
    free(str);
    return OK_ATOM;
}

static term nif_m5_display_println(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (!term_is_binary(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    char *str = interop_binary_to_string(argv[0]);
    if (!str) {
        RAISE_ERROR(BADARG_ATOM);
    }
    atomvm_m5_display_println(str);
    free(str);
    return OK_ATOM;
}

static term nif_m5_display_fill_screen(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (!term_is_integer(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    atomvm_m5_display_fill_screen((unsigned int) term_to_int(argv[0]));
    return OK_ATOM;
}

static term nif_m5_display_set_cursor(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (!term_is_integer(argv[0]) || !term_is_integer(argv[1])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    atomvm_m5_display_set_cursor(term_to_int(argv[0]), term_to_int(argv[1]));
    return OK_ATOM;
}

static term nif_m5_display_set_text_size(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (!term_is_integer(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    atomvm_m5_display_set_text_size(term_to_int(argv[0]));
    return OK_ATOM;
}

static term nif_m5_display_set_text_color(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    if (!term_is_integer(argv[0])) {
        RAISE_ERROR(BADARG_ATOM);
    }
    atomvm_m5_display_set_text_color((unsigned int) term_to_int(argv[0]));
    return OK_ATOM;
}

static term nif_m5_btn_a_is_pressed(Context *ctx, int argc, term argv[])
{
    UNUSED(argc);
    UNUSED(argv);
    return atomvm_m5_btn_a_is_pressed() ? TRUE_ATOM : FALSE_ATOM;
}

static const struct Nif m5_begin_nif             = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_begin };
static const struct Nif m5_update_nif            = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_update };
static const struct Nif m5_display_print_nif     = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_display_print };
static const struct Nif m5_display_println_nif   = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_display_println };
static const struct Nif m5_display_fill_screen_nif    = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_display_fill_screen };
static const struct Nif m5_display_set_cursor_nif     = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_display_set_cursor };
static const struct Nif m5_display_set_text_size_nif  = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_display_set_text_size };
static const struct Nif m5_display_set_text_color_nif = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_display_set_text_color };
static const struct Nif m5_btn_a_is_pressed_nif  = { .base.type = NIFFunctionType, .nif_ptr = nif_m5_btn_a_is_pressed };

static const struct Nif *m5unified_nif_get_nif(const char *nifname)
{
    if (strcmp("m5:begin/0", nifname) == 0)                  { TRACE("Resolved %s\n", nifname); return &m5_begin_nif; }
    if (strcmp("m5:update/0", nifname) == 0)                 { TRACE("Resolved %s\n", nifname); return &m5_update_nif; }
    if (strcmp("m5:display_print/1", nifname) == 0)          { TRACE("Resolved %s\n", nifname); return &m5_display_print_nif; }
    if (strcmp("m5:display_println/1", nifname) == 0)        { TRACE("Resolved %s\n", nifname); return &m5_display_println_nif; }
    if (strcmp("m5:display_fill_screen/1", nifname) == 0)    { TRACE("Resolved %s\n", nifname); return &m5_display_fill_screen_nif; }
    if (strcmp("m5:display_set_cursor/2", nifname) == 0)     { TRACE("Resolved %s\n", nifname); return &m5_display_set_cursor_nif; }
    if (strcmp("m5:display_set_text_size/1", nifname) == 0)  { TRACE("Resolved %s\n", nifname); return &m5_display_set_text_size_nif; }
    if (strcmp("m5:display_set_text_color/1", nifname) == 0) { TRACE("Resolved %s\n", nifname); return &m5_display_set_text_color_nif; }
    if (strcmp("m5:btn_a_is_pressed/0", nifname) == 0)       { TRACE("Resolved %s\n", nifname); return &m5_btn_a_is_pressed_nif; }
    return NULL;
}

REGISTER_NIF_COLLECTION(m5unified, NULL, NULL, m5unified_nif_get_nif)

#endif
