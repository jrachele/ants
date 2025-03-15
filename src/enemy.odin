package ants

import "core:math"
import rl "vendor:raylib"

Enemy :: struct {
	using creature: Creature,
}

EnemyMetadata :: struct {
	using creature_meta: CreatureMetadata,
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
	enemy.pos = rl.Vector2Rotate({ENEMY_SPAWN_RADIUS, 0}, random_angle) + NEST_POS
	enemy.direction = rl.Vector2Normalize(NEST_POS - enemy.pos)
	enemy.health = enemy_data.initial_health
	enemy.life_time = enemy_data.initial_life
	enemy.speed = enemy_data.initial_speed

	return
}

spawn_enemy :: proc(state: ^GameState, immediately: bool = false) {
	enemy := init_enemy()
	if immediately {
		enemy.life_time = 0
	}

	append(&state.enemies, enemy)
}

update_enemies :: proc(state: ^GameState) {
	if state.paused do return
	for &enemy, i in state.enemies {
		if enemy.health <= 0 {
			ordered_remove(&state.enemies, i)
			continue
		}
		if is_in_nest(enemy.pos) {
			// Deal damage to the nest 
			state.nest.health -= 1
			ordered_remove(&state.enemies, i)
			continue
		}

		// TODO: Make enemies look realistic and shit
		if !walk_creature(&enemy, state.grid) {
			turn_creature(&enemy, Direction.Right)
		} else {
			enemy.direction = rl.Vector2Normalize(
				rl.Vector2Rotate(NEST_POS - enemy.pos, get_random_value_f(-0.05, 0.05)),
			)
		}
	}
}

draw_enemies :: proc(state: GameState) {
	for enemy in state.enemies {
		draw_creature(enemy, Default_Enemy)
	}
}
