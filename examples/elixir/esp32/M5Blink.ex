# SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

defmodule M5Blink do
  @compile {:no_warn_undefined, [M5]}

  def start() do
    M5.begin()
    M5.display_fill_screen(M5.black())
    M5.display_set_text_size(2)
    M5.display_set_text_color(M5.white())
    M5.display_set_cursor(0, 0)
    M5.display_println("Hello AtomS3!")
    loop(0)
  end

  defp loop(count) do
    M5.update()
    state = if rem(count, 2) == 0, do: "ON", else: "OFF"
    color = if rem(count, 2) == 0, do: M5.green(), else: M5.red()
    M5.display_set_cursor(0, 40)
    M5.display_set_text_color(M5.white())
    M5.display_println("Count: #{count}   ")
    M5.display_set_text_color(color)
    M5.display_println("LED: #{state}  ")
    Process.sleep(1000)
    loop(count + 1)
  end
end
