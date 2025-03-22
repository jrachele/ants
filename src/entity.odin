package ants

import "core:math"
import rl "vendor:raylib"

ENTITY_ALPHA :: 200

Entity :: struct {
	pos:       Vector2,
	direction: Vector2,
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
