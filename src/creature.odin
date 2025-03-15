package ants

import "core:math"
import rl "vendor:raylib"

CREATURE_ALPHA :: 200
Creature :: struct {
	pos:       rl.Vector2,
	direction: rl.Vector2,
	speed:     f32,
	health:    f32,
	life_time: f32,
}

CreatureMetadata :: struct {
	color:          rl.Color,
	size:           f32,
	initial_speed:  f32,
	initial_life:   f32, // Initial life stage when spawned 
	average_life:   f32, // Average life stage until health deteriorates 
	initial_health: f32,
}

turn_creature :: proc {
	turn_creature_direction,
	turn_creature_v2,
}

SLIGHT_TURN :: math.PI / 6
HARD_TURN :: math.PI / 2

turn_creature_direction :: proc(creature: ^Creature, direction: Direction) {
	rotation_random_offset := get_random_value_f(-0.1, 0.1)
	switch (direction) {
	case .Left:
		creature.direction = rl.Vector2Rotate(
			creature.direction,
			-SLIGHT_TURN + rotation_random_offset,
		)
	case .Right:
		creature.direction = rl.Vector2Rotate(
			creature.direction,
			SLIGHT_TURN + rotation_random_offset,
		)
	case .Forward:
		creature.direction = rl.Vector2Rotate(creature.direction, rotation_random_offset)
	case .Around:
		left := bool(rl.GetRandomValue(0, 1))
		if left {
			creature.direction = rl.Vector2Rotate(
				creature.direction,
				-HARD_TURN + rotation_random_offset,
			)
		} else {
			creature.direction = rl.Vector2Rotate(
				creature.direction,
				HARD_TURN + rotation_random_offset,
			)
		}
	}
}

turn_creature_v2 :: proc(creature: ^Creature, direction: rl.Vector2) {
	rotation_random_offset := get_random_value_f(-0.05, 0.05)
	creature.direction = rl.Vector2Rotate(direction, rotation_random_offset)
}

walk_creature :: proc(creature: ^Creature, grid: Grid) -> bool {
	// Ensure there is nothing in the way
	front_block_pos := get_front_block(creature^)
	block, block_real := get_block(grid, expand_values(front_block_pos))

	// Move forward if we're good 
	if block_real && is_block_permeable(block.type) {
		prev_pos := creature.pos
		creature.pos += creature.direction * rl.GetFrameTime() * creature.speed
		return true
	}
	// Otherwise we didn't move at all
	return false
}
