package ants

import "core:math"
import rl "vendor:raylib"

ENTITY_ALPHA :: 200

Entity :: struct {
	pos:       rl.Vector2,
	direction: rl.Vector2,
	// TODO: Consider dynamically allocating memory for the stack
	actions:   Action_Stack,
	speed:     f32,
	health:    f32,
	life_time: f32,
}

EntityMetadata :: struct {
	color:          rl.Color,
	size:           f32,
	initial_speed:  f32,
	initial_life:   f32, // Initial life stage when spawned 
	average_life:   f32, // Average life stage until health deteriorates 
	initial_health: f32,
}

turn_entity :: proc {
	turn_entity_direction,
	turn_entity_v2,
}

SLIGHT_TURN :: math.PI / 6
HARD_TURN :: math.PI / 2

turn_entity_direction :: proc(entity: ^Entity, direction: Direction) {
	rotation_random_offset := get_random_value_f(-0.1, 0.1)
	switch (direction) {
	case .Left:
		entity.direction = rl.Vector2Rotate(
			entity.direction,
			-SLIGHT_TURN + rotation_random_offset,
		)
	case .Right:
		entity.direction = rl.Vector2Rotate(entity.direction, SLIGHT_TURN + rotation_random_offset)
	case .Forward:
		entity.direction = rl.Vector2Rotate(entity.direction, rotation_random_offset)
	case .Around:
		left := bool(rl.GetRandomValue(0, 1))
		if left {
			entity.direction = rl.Vector2Rotate(
				entity.direction,
				-HARD_TURN + rotation_random_offset,
			)
		} else {
			entity.direction = rl.Vector2Rotate(
				entity.direction,
				HARD_TURN + rotation_random_offset,
			)
		}
	}
}

turn_entity_v2 :: proc(entity: ^Entity, direction: rl.Vector2) {
	rotation_random_offset := get_random_value_f(-0.05, 0.05)
	entity.direction = rl.Vector2Rotate(direction, rotation_random_offset)
}

walk_entity :: proc(entity: ^Entity, grid: Grid) -> bool {
	// Ensure there is nothing in the way
	front_block_pos := get_front_block(entity^)
	block, block_real := get_block(grid, expand_values(front_block_pos))

	// Move forward if we're good 
	if block_real && is_block_permeable(block.type) {
		prev_pos := entity.pos
		entity.pos += entity.direction * rl.GetFrameTime() * entity.speed
		return true
	}
	// Otherwise we didn't move at all
	return false
}
