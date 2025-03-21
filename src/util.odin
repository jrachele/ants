package ants

import "core:strings"
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

get_random_vec :: proc(min, max: f32) -> rl.Vector2 {
	return {get_random_value_f(min, max), get_random_value_f(min, max)}
}

flip_coin :: proc() -> bool {
	return rl.GetRandomValue(0, 1) == 0
}

draw_text_align :: proc(
	font: rl.Font,
	text: string,
	x: i32,
	y: i32,
	alignment: Text_Alignment,
	font_size: i32,
	color: rl.Color,
) {
	font_size := f32(font_size)
	x := f32(x)
	y := f32(y)

	text_cstr := strings.clone_to_cstring(text)
	defer delete(text_cstr)

	text_size := rl.MeasureTextEx(font, text_cstr, font_size, 0)
	position := rl.Vector2{x, y}
	switch (alignment) {
	case .Left:
	// Keep it the same
	case .Center:
		position -= text_size / 2
	case .Right:
		position -= text_size
	}

	rl.DrawTextEx(font, text_cstr, position, font_size, 0, color)
}


random_select :: proc(possible_values: []$T) -> T {
	if len(possible_values) == 0 {
		panic("Random select on empty possible values")
	}

	index := rl.GetRandomValue(0, i32(len(possible_values) - 1))
	return possible_values[index]
}
