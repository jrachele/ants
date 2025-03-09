package ants

import rl "vendor:raylib"

Text_Alignment :: enum {
	Left,
	Center,
	Right,
}

get_random_float :: proc(precision: u32 = 1000) -> f32 {
	return f32(rl.GetRandomValue(0, i32(precision))) / f32(precision)
}

get_random_value_f :: proc(min, max: f32) -> f32 {
	range := max - min
	return (get_random_float() * range) + min
}

draw_text_align :: proc(
	font: rl.Font,
	text: cstring,
	x: i32,
	y: i32,
	alignment: Text_Alignment,
	font_size: i32,
	color: rl.Color,
) {
	x := x
	text_size := rl.MeasureText(text, font_size)
	switch (alignment) {
	case .Left:
		x -= text_size
	case .Center:
		x -= (text_size / 2)
	case .Right:
	// Keep it the same
	}

	rl.DrawText(text, x, y, font_size, color)
}
