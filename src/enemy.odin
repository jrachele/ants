package ants

import "core:math"
import rl "vendor:raylib"

Enemy :: struct {
	using entity: Entity,
}

EnemyMetadata :: struct {
	using entity_meta: EntityMetadata,
}

Default_Enemy :: EnemyMetadata {
	size           = 2,
	initial_speed  = 10,
	color          = rl.RED,
	initial_life   = 0,
	average_life   = 1000,
	initial_health = 10,
}


ENEMY_SPAWN_RADIUS :: 300
init_enemy :: proc() -> (enemy: Enemy) {
	// TODO: Eventually create different enemy types
	enemy_data := Default_Enemy

	// Generate the enemy position on a ring about the nest 
	random_angle := get_random_value_f(0, math.PI * 2)
	enemy.pos = vector2_rotate({ENEMY_SPAWN_RADIUS, 0}, random_angle) + NEST_POS
	enemy.direction = vector2_normalize(NEST_POS - enemy.pos)
	enemy.health = enemy_data.initial_health
	enemy.life_time = enemy_data.initial_life
	enemy.speed = enemy_data.initial_speed

	return
}

spawn_enemy :: proc(data: ^GameData, immediately: bool = false) {
	enemy := init_enemy()
	if immediately {
		enemy.life_time = 0
	}

	append(&data.enemies, enemy)
}
