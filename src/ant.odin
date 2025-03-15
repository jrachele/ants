package ants

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

ANT_IDLE_TIME :: 0.300

// milliseconds
ANT_SPAWN_RATE :: 5000

AntType :: enum {
	Peon,
	Armored,
	Porter,
	Elite,
}

Ant :: struct {
	using creature:           Creature,
	pheromone_time_remaining: f32,
	load:                     f32,
	load_type:                EnvironmentType,
	type:                     AntType,
	state:                    AntState,
	objective:                AntObjective,
	selected:                 bool,
}

AntMetadata :: struct {
	using creature_meta: CreatureMetadata,
	carrying_capacity:   f32,
	spawn_cost:          f32,
	load_speed:          f32,
}

AntValues := [AntType]AntMetadata {
	.Peon = AntMetadata {
		size = 1,
		initial_speed = 15,
		color = rl.BLACK,
		initial_life = -10,
		average_life = 60,
		initial_health = 5,
		carrying_capacity = 5,
		spawn_cost = 0,
		load_speed = 2,
	},
	.Armored = AntMetadata {
		size = 2,
		initial_speed = 10,
		color = rl.DARKGRAY,
		initial_life = -20,
		average_life = 300,
		initial_health = 100,
		carrying_capacity = 15,
		spawn_cost = 10,
		load_speed = 5,
	},
	.Porter = AntMetadata {
		size = 2,
		initial_speed = 15,
		color = rl.GREEN,
		initial_life = -20,
		average_life = 300,
		initial_health = 30,
		carrying_capacity = 100,
		spawn_cost = 10,
		load_speed = 20,
	},
	.Elite = AntMetadata {
		size = 4,
		initial_speed = 10,
		color = rl.BLUE,
		initial_life = -50,
		average_life = 1000,
		initial_health = 1000,
		carrying_capacity = 0,
		spawn_cost = 100,
		load_speed = 0,
	},
}

AntState_Walk :: struct {
	target_pos: rl.Vector2,
}
AntState_Idle :: struct {
	idle_time_remaining: f32,
}
AntState_Fight :: struct {
	enemy: ^Enemy,
}
AntState_Load :: struct {}
AntState_Unload :: struct {}

AntState :: union {
	AntState_Idle, // Pause for a second and analyze the neighborhood 
	AntState_Walk, // Walk forwards toward direction vector, with random variations
	AntState_Fight, // Actively move towards an enemy and do damage to it
	AntState_Load, // Load / unload supply
	AntState_Unload, // Load / unload supply
}

AntObjective_Explore :: struct {}
AntObjective_War :: struct {}
AntObjective_Forage :: struct {
	forage_type: EnvironmentType,
}
AntObjective_Build :: struct {} // TODO: Add build operation here

AntReturnReason :: enum {
	Danger,
	FullLoad,
}

AntObjective_Return :: struct {
	reason: AntReturnReason,
}

AntObjective :: union {
	AntObjective_Explore, // Go randomly in whatever direction 
	AntObjective_Forage, // Go look for something
	AntObjective_Build, // Build one of the designated items/fortifications
	AntObjective_Return, // Go back to the nest
	AntObjective_War, // Follow danger pheromones and fight 
}

init_ant :: proc(type: AntType, nest: Nest) -> (ant: Ant) {
	ant_data := AntValues[type]
	ant.pos = NEST_POS
	// Initially, the ants can go wherever
	ant.direction = rl.Vector2Normalize(get_random_vec(-1, 1))
	ant.type = type
	ant.health = ant_data.initial_health
	ant.life_time = ant_data.initial_life
	ant.speed = ant_data.initial_speed
	ant.objective = roll_ant_objective(nest)
	// Default to the idle state
	set_ant_state(&ant, AntState_Idle{})
	return
}

spawn_ant :: proc(state: ^GameState, type: AntType = AntType.Peon, immediately: bool = false) {
	ant := init_ant(type, state.nest)
	if immediately {
		ant.life_time = 0
	}

	append(&state.ants, ant)
}

ATTACK_DISTANCE :: 5
PURSUIT_DISTANCE :: 20

update_ants :: proc(state: ^GameState) {
	mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	for &ant in state.ants {
		ant_data := AntValues[ant.type]
		if ant.life_time < 0 do continue
		ant.selected = rl.Vector2Distance(mouse_pos, ant.pos) < ant_data.size
	}

	if state.paused do return

	for &ant, i in state.ants {
		ant_data := AntValues[ant.type]

		ant.life_time += rl.GetFrameTime()
		if (ant.life_time < 0) do continue
		if (ant.life_time > ant_data.average_life) {
			ant.health -= rl.GetFrameTime()
		}

		if (ant.health < 0) {
			ordered_remove(&state.ants, i)
			continue
		}

		// If any enemies are in the area, immediately go into war mode
		found_enemy := false
		for enemy in state.enemies {
			distance := rl.Vector2Distance(ant.pos, enemy.pos)
			if distance < PURSUIT_DISTANCE {
				found_enemy = true
				break
			}
		}

		// TODO: Use pheromones and actually make this proper
		if found_enemy {
			set_ant_state(&ant, AntState_Fight{})
		} else {
			// _, is_at_war := ant.objective.(AntObjective_War)
			// if is_at_war {
			// 	// Stop warring if no enemies in sight
			// 	ant.objective = roll_ant_objective(state.nest)
			// 	set_ant_state(&ant, AntState_Idle{})
			// }
		}

		// Handle ant states
		switch &ant_state in ant.state {
		case AntState_Walk:
			if rl.Vector2Distance(ant_state.target_pos, ant.pos) <=
			   min((GRID_CELL_SIZE / 2), ant_data.size) {
				// If the ant has reached the target position, idle
				set_ant_state(&ant, AntState_Idle{})
				break
			}

			turn_creature(&ant, Direction.Forward)

			// Lock the direction back in if the ant has strayed too far away from the target position
			direction := rl.Vector2Normalize(ant_state.target_pos - ant.pos)
			if abs(rl.Vector2Angle(ant.direction, direction)) > math.PI / 4 {
				turn_creature(&ant, direction)
			}

			// If the ant was unable to walk due to an obstacle, idle
			if !walk_creature(&ant, state.grid) {
				set_ant_state(&ant, AntState_Idle{})
			}

		case AntState_Fight:
			if found_enemy == false {
				set_ant_state(&ant, AntState_Idle{})
				break
			}
			for &enemy in state.enemies {
				distance := rl.Vector2Distance(ant.pos, enemy.pos)
				if distance < PURSUIT_DISTANCE {
					turn_creature(&ant, rl.Vector2Normalize(enemy.pos - ant.pos))
					walk_creature(&ant, state.grid)

					if distance < ATTACK_DISTANCE {
						enemy.health -= 1
					}

					break
				}
			}
		case AntState_Load:
			front_block_position := get_front_block(ant)
			block := get_block_ptr(&state.grid, expand_values(front_block_position))

			// If the ant is hauling, it's taking whatever block is in the middle
			if (block.amount <= 0 || block.type == .Nothing) {
				set_ant_state(&ant, AntState_Idle{})
				break
			}

			ant.load_type = block.type

			// Get a mutable m block as we need to modify the grid
			amount := min(ant_data.load_speed * rl.GetFrameTime(), block.amount)
			ant.load += amount
			block.amount -= amount

			try_spread_pheromone(&ant, &state.grid, .Forage)

			// If the ant has exceeded its load limit, return it to idle 
			if (ant_data.carrying_capacity != 0 && ant.load >= ant_data.carrying_capacity) {
				set_ant_state(&ant, AntState_Idle{})
			}
		case AntState_Unload:
			// The ant should not be in the unload state unless they are in nest
			if (!is_in_nest(ant.pos)) {
				set_ant_state(&ant, AntState_Idle{})
				break
			}

			amount := min(ant_data.load_speed * rl.GetFrameTime(), ant.load)
			state.nest.inventory[ant.load_type] += amount
			ant.load -= amount

			try_spread_pheromone(&ant, &state.grid, .General)

			if ant.load <= 0 {
				set_ant_state(&ant, AntState_Idle{})
			}
		case AntState_Idle:
			// In the idle state, the ant has to make its major decisions 
			// depending on its objective. If it has fulfilled its objective, it will be assigned a new one 
			ant_state.idle_time_remaining -= rl.GetFrameTime()
			front_block_index := get_front_block(ant)
			front_block, exists := get_block(state.grid, expand_values(front_block_index))

			// FIXME: There is an explicit coupling here, this system is not good
			desired_block, is_searching := ant.objective.(AntObjective_Forage)
			if is_searching {
				if desired_block.forage_type != front_block.type &&
				   !is_block_permeable(front_block.type) {
					// Get out tha wayyyyy
					turn_creature(&ant, Direction.Right)
					ant_wander(&ant)
				}
			}


			neighborhood := get_neighborhood(ant, state^)
			defer delete(neighborhood)

			if len(neighborhood) == 0 {
				// The ant is in an impossible state!, remove it
				ordered_remove(&state.ants, i)
				continue
			}

			switch &ant_objective in ant.objective {
			case AntObjective_Build:
				// TODO: Implement building, but for now set the objective to forage 
				ant.objective = AntObjective_Forage {
					forage_type = .Honey,
				}
			case AntObjective_War:
				// TODO: Actually engage any found enemies 
				most_danger_pheromone_pos :=
					find_most_pheromones(&ant, neighborhood, state.grid, .Danger) +
					{GRID_CELL_SIZE / 2, GRID_CELL_SIZE / 2}
				ant_walk_towards_pos(&ant, most_danger_pheromone_pos)
			case AntObjective_Forage:
				if ant_data.carrying_capacity == 0 || ant.load >= ant_data.carrying_capacity {
					ant.objective = AntObjective_Return {
						reason = .FullLoad,
					}
					set_ant_state(&ant, AntState_Walk{target_pos = NEST_POS})
					break
				}

				front_block_position := get_front_block(ant)
				block, block_exists := get_block(state.grid, expand_values(front_block_position))

				// If we have successfully stopped in front of our forage type
				if block_exists && block.type == ant_objective.forage_type {
					// ensure we are in the loading state
					ant.load_type = block.type
					set_ant_state(&ant, AntState_Load{})
				} else if block_exists && !is_block_permeable(block.type) {
					// Edge case where we've idled because we hit a block
				} else {
					// FIXME: Don't recalculate the item neighborhood if we simply hit a wall
					// otherwise seek the block in the neighborhood
					item_pos :=
						find_item(&ant, neighborhood, state.grid, ant_objective.forage_type) +
						{GRID_CELL_SIZE / 2, GRID_CELL_SIZE / 2}
					ant_walk_towards_pos(&ant, item_pos)
				}
			case AntObjective_Return:
				if (is_in_nest(ant.pos)) {
					if ant.load <= 0 {
						// We have completed our return and are ready for a new objective.
						assign_ant_new_objective(&ant, state.nest)
						break
					}

					// Otherwise we need to ensure we are in the unload ant state
					set_ant_state(&ant, AntState_Unload{})
					break
				}

				// If we are not at the nest, we should return, placing pheromones along the way depending on why we returned
				// general_pheromone_pos := find_most_pheromones(
				// 	&ant,
				// 	neighborhood,
				// 	state.grid,
				// 	.General,
				// ) +
				// {GRID_CELL_SIZE / 2, GRID_CELL_SIZE / 2}
				// ant_walk_towards_pos(&ant, general_pheromone_pos)

				// TODO: Somehow following the general pheromones has to work a bit better
				// For now this cheat will make things a lot smoother
				ant_walk_towards_pos(&ant, NEST_POS)

				pheromone: Pheromone
				switch ant_objective.reason {
				case .Danger:
					pheromone = .Danger
				case .FullLoad:
					pheromone = .Forage
				}
				try_spread_pheromone(&ant, &state.grid, pheromone)
			case AntObjective_Explore:
				// TODO: Exploring ants can be drafted for war or building at any time
				ant_wander(&ant)
			}
		}

		// Update timers
		ant.pheromone_time_remaining -= rl.GetFrameTime()
	}

	// Spawn ants here 
	// TODO: Remove the spawn timer and make something more flexible 
	if time.stopwatch_duration(state.timer) > ANT_SPAWN_RATE * time.Millisecond {
		inventory := &state.nest.inventory

		possible_spawn := -1 // 0 -> peon
		for type in AntType {
			ant_data := AntValues[type]
			if inventory[.Honey] >= ant_data.spawn_cost {
				possible_spawn += 1
			}
		}

		if possible_spawn == -1 {
			// Queen cant birth any more ants 
			return
		}

		random_type := rl.GetRandomValue(0, i32(possible_spawn))
		spawn_type := AntType(random_type)

		inventory[.Honey] -= AntValues[spawn_type].spawn_cost
		spawn_ant(state, spawn_type)

		// TODO: Move spawning of all creatures somewhere else 
		spawn_enemy(state)

		time.stopwatch_reset(&state.timer)
		time.stopwatch_start(&state.timer)
	}
}

set_ant_state :: proc(ant: ^Ant, state: AntState) {
	// If we are setting the state to an idle state, set a proper default idle_time_remaining
	idle_state, ok := state.(AntState_Idle)
	if (ok) {
		if idle_state.idle_time_remaining == 0 {
			idle_state.idle_time_remaining = ANT_IDLE_TIME + get_random_value_f(-0.1, 0.1)
		}
	}

	ant.state = state
}

ant_wander :: proc(ant: ^Ant) {
	// Walk some random distance
	random_pos := ant.pos + ant.direction * get_random_value_f(3, 20)
	set_ant_state(ant, AntState_Walk{target_pos = random_pos})
}

ant_walk_towards_pos :: proc(ant: ^Ant, pos: rl.Vector2) {
	if pos == {-1, -1} {
		ant_wander(ant)
	} else {
		set_ant_state(ant, AntState_Walk{target_pos = pos})
	}
}

assign_ant_new_objective :: proc(ant: ^Ant, nest: Nest) {
	new_ant_objective := roll_ant_objective(nest)
	ant.objective = new_ant_objective
}


draw_ants :: proc(state: GameState) {
	for ant in state.ants {
		draw_ant(ant)

		when ODIN_DEBUG {
			if debug_overlay {
				// Draw neighborhood 
				neighborhood := get_neighborhood(ant, state)
				defer delete(neighborhood)

				for index in neighborhood {
					pos := get_world_position_from_block_index(index)
					color := rl.RED
					color.a = 50
					rl.DrawRectangleV(pos, GRID_CELL_SIZE, color)
				}

				pos := get_front_block(ant) * GRID_CELL_SIZE
				color := rl.YELLOW
				color.a = 100
				rl.DrawRectangle(pos.x, pos.y, GRID_CELL_SIZE, GRID_CELL_SIZE, color)


				when ODIN_DEBUG {
					if debug_overlay {
						walk, walking := ant.state.(AntState_Walk)
						if walking {
							rl.DrawCircleV(walk.target_pos, 1, rl.SKYBLUE)
						}
					}
				}

			}
		}
	}
}

draw_creature :: proc(creature: Creature, metadata: CreatureMetadata) -> bool {
	if creature.life_time < 0 {
		// Creatures that haven't been born won't be drawn
		return false
	}

	color := metadata.color
	color.a = CREATURE_ALPHA

	// Lower body 
	rl.DrawCircleV(creature.pos, metadata.size / 2, color)
	// Abdomen
	rl.DrawCircleV(
		creature.pos + (metadata.size * creature.direction / 2),
		metadata.size / 4,
		color,
	)
	// Head
	rl.DrawCircleV(creature.pos + (metadata.size * creature.direction), metadata.size / 3, color)

	return true
}

draw_ant :: proc(ant: Ant) {
	ant_data := AntValues[ant.type]

	if !draw_creature(ant, ant_data) {
		return
	}

	if ant.selected {
		rl.DrawCircleLinesV(ant.pos, ant_data.size, rl.WHITE)
	}

	// Load if any
	if (ant.load > 0) {
		block_color := get_block_color(ant.load_type)
		rl.DrawCircleV(
			ant.pos + (ant_data.size * ant.direction * 2),
			ant_data.size / 4,
			block_color,
		)
	}
}

draw_ant_data :: proc(ant: Ant) {
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	ant_data := AntValues[ant.type]
	// TODO: Draw health bar
	if ant.life_time < 0 {
		fmt.sbprintfln(&sb, "%v (%.2fs)", ant.type, ant.life_time * -1.0)
	} else {
		fmt.sbprintfln(&sb, "%v", ant.type)
	}

	when ODIN_DEBUG {
		fmt.sbprintfln(&sb, "%v", ant)
	}

	label_str := strings.to_string(sb)

	// TODO: Get different font working 
	draw_text_align(
		rl.GetFontDefault(),
		label_str,
		i32(ant.pos.x),
		i32(ant.pos.y),
		.Center,
		i32(ant_data.size),
		rl.Color{0, 0, 0, 180},
	)

}
