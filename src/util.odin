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
	text_cstr := strings.clone_to_cstring(text)
	defer delete(text_cstr)

	x := x
	text_size := rl.MeasureText(text_cstr, font_size)
	switch (alignment) {
	case .Left:
	// Keep it the same
	case .Center:
		x -= (text_size / 2)
	case .Right:
		x -= text_size
	}

	rl.DrawText(text_cstr, x, y, font_size, color)
}


random_select :: proc(possible_values: []$T) -> T {
	if len(possible_values) == 0 {
		panic("Random select on empty possible values")
	}

	index := rl.GetRandomValue(0, i32(len(possible_values) - 1))
	return possible_values[index]
}
