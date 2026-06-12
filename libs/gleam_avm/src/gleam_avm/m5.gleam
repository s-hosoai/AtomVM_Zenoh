pub const black = 0x000000
pub const white = 0xFFFFFF
pub const red = 0xFF0000
pub const green = 0x00FF00
pub const blue = 0x0000FF
pub const yellow = 0xFFFF00
pub const cyan = 0x00FFFF
pub const magenta = 0xFF00FF

@external(erlang, "m5", "begin")
pub fn begin() -> Nil

@external(erlang, "m5", "update")
pub fn update() -> Nil

@external(erlang, "m5", "display_print")
pub fn display_print(text: String) -> Nil

@external(erlang, "m5", "display_println")
pub fn display_println(text: String) -> Nil

@external(erlang, "m5", "display_fill_screen")
pub fn display_fill_screen(color: Int) -> Nil

@external(erlang, "m5", "display_set_cursor")
pub fn display_set_cursor(x: Int, y: Int) -> Nil

@external(erlang, "m5", "display_set_text_size")
pub fn display_set_text_size(size: Int) -> Nil

@external(erlang, "m5", "display_set_text_color")
pub fn display_set_text_color(color: Int) -> Nil

@external(erlang, "m5", "btn_a_is_pressed")
pub fn btn_a_is_pressed() -> Bool
