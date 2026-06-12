/*
 * SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
 */

#include <sdkconfig.h>
#ifdef CONFIG_AVM_ENABLE_M5UNIFIED_NIFS

#include <M5Unified.h>
#include <string.h>

extern "C" void atomvm_m5_begin(void)
{
    auto cfg = M5.config();
    // Disable I2C-based internal peripherals to avoid conflict with
    // AtomVM's legacy I2C driver (i2c_driver_install vs i2c_master).
    cfg.internal_imu = false;
    cfg.internal_rtc = false;
    M5.begin(cfg);
}

extern "C" void atomvm_m5_update(void)
{
    M5.update();
}

extern "C" void atomvm_m5_display_print(const char *text)
{
    M5.Display.print(text);
}

extern "C" void atomvm_m5_display_println(const char *text)
{
    M5.Display.println(text);
}

extern "C" void atomvm_m5_display_fill_screen(uint32_t color)
{
    M5.Display.fillScreen(color);
}

extern "C" void atomvm_m5_display_set_cursor(int x, int y)
{
    M5.Display.setCursor(x, y);
}

extern "C" void atomvm_m5_display_set_text_size(int size)
{
    M5.Display.setTextSize(size);
}

extern "C" void atomvm_m5_display_set_text_color(uint32_t color)
{
    M5.Display.setTextColor(color);
}

extern "C" int atomvm_m5_btn_a_is_pressed(void)
{
    return M5.BtnA.isPressed() ? 1 : 0;
}

#endif
