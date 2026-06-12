# SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later

defmodule M5 do
  @compile {:no_warn_undefined, [:m5]}

  @moduledoc """
  Elixir wrapper for AtomVM M5Unified NIFs.

  Provides access to M5Stack device features including display and buttons
  via the m5 NIF module backed by the M5Unified C++ library.
  """

  @black   0x000000
  @white   0xFFFFFF
  @red     0xFF0000
  @green   0x00FF00
  @blue    0x0000FF
  @yellow  0xFFFF00
  @cyan    0x00FFFF
  @magenta 0xFF00FF

  def black(),   do: @black
  def white(),   do: @white
  def red(),     do: @red
  def green(),   do: @green
  def blue(),    do: @blue
  def yellow(),  do: @yellow
  def cyan(),    do: @cyan
  def magenta(), do: @magenta

  @doc "Initialize M5Stack device."
  def begin(), do: :m5.begin()

  @doc "Update button and touch state. Call periodically."
  def update(), do: :m5.update()

  @doc "Print text at the current cursor position."
  def display_print(text), do: :m5.display_print(text)

  @doc "Print text followed by a newline."
  def display_println(text), do: :m5.display_println(text)

  @doc "Fill the entire screen with the given RGB888 color integer."
  def display_fill_screen(color), do: :m5.display_fill_screen(color)

  @doc "Move the text cursor to (x, y)."
  def display_set_cursor(x, y), do: :m5.display_set_cursor(x, y)

  @doc "Set the text size multiplier (1, 2, 3 ...)."
  def display_set_text_size(size), do: :m5.display_set_text_size(size)

  @doc "Set the text foreground color as an RGB888 integer."
  def display_set_text_color(color), do: :m5.display_set_text_color(color)

  @doc "Return true if button A is currently pressed."
  def btn_a_is_pressed(), do: :m5.btn_a_is_pressed()
end
