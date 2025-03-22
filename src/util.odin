package ants

import "base:intrinsics"
import "core:math"
import "core:math/rand"
import "core:strings"

Vector2 :: [2]f32

get_random_value_f :: proc(min, max: f32) -> f32 {
	return rand.float32_range(min, max)
}

get_random_vec :: proc(min, max: f32) -> Vector2 {
	return {get_random_value_f(min, max), get_random_value_f(min, max)}
}

flip_coin :: proc() -> bool {
	return random_select([]bool{false, true})
}

random_select :: proc {
	rand.choice_enum,
	rand.choice,
}

// Randomly select from a group, giving priority to the prioritized item
// priority: (0, 1) where 0 is no priority at all, and 1 is full priority
random_select_priority :: proc(priority: f32, prioritized_item: $T, remaining_items: []T) -> T {
	roll := rand.float32()
	if roll < priority {
		return prioritized_item
	} else {
		return random_select(remaining_items)
	}
}

vector2_rotate :: proc(v: Vector2, rads: f32) -> Vector2 {
	return {
		v.x * math.cos(rads) - v.y * math.sin(rads),
		v.x * math.sin(rads) + v.y * math.cos(rads),
	}
}

vector2_distance_squared :: proc(v1: Vector2, v2: Vector2) -> f32 {
	return (v2.x - v1.x) * (v2.x - v1.x) + (v2.y - v1.y) * (v2.y - v1.y)
}

vector2_distance :: proc(v1: Vector2, v2: Vector2) -> f32 {
	return math.sqrt(vector2_distance_squared(v1, v2))
}

vector2_length :: proc(v1: Vector2) -> f32 {
	return vector2_distance(v1, {0, 0})
}

vector2_normalize :: proc(v1: Vector2) -> Vector2 {
	length := vector2_length(v1)
	if length > 0 {
		return v1 / length
	}
	return {}
}
