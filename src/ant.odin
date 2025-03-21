package ants

import sm "core:container/small_array"
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
	using entity:             Entity,
	pheromone_time_remaining: f32,
	load:                     f32,
	load_type:                EnvironmentType,
	type:                     AntType,
	objective:                AntObjective,
	selected:                 bool,
}

AntMetadata :: struct {
	using entity_meta: EntityMetadata,
	carrying_capacity: f32,
	spawn_cost:        f32,
	load_speed:        f32,
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
	return
}

spawn_ant :: proc(data: ^GameData, type: AntType = AntType.Peon, immediately: bool = false) {
	ant := init_ant(type, data.nest)
	if immediately {
		ant.life_time = 0
	}

	append(&data.ants, ant)
}

ATTACK_DISTANCE :: 5
PURSUIT_DISTANCE :: 20

update_ants :: proc(data: ^GameData) {
	mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	for &ant in data.ants {
		ant_data := AntValues[ant.type]
		if ant.life_time < 0 do continue
		ant.selected = rl.Vector2Distance(mouse_pos, ant.pos) < ant_data.size
	}

	if data.paused do return

	for &ant, i in data.ants {
		ant_data := AntValues[ant.type]

		ant.life_time += rl.GetFrameTime()
		if (ant.life_time < 0) do continue
		if (ant.life_time > ant_data.average_life) {
			ant.health -= rl.GetFrameTime()
		}

		if (ant.health < 0) {
			ordered_remove(&data.ants, i)
			continue
		}

		#partial switch objective in ant.objective {
		case AntObjective_Forage:
			if has_no_actions(ant) {
				// If we have no actions, queue up the set of foraging actions 
				// queue_action_sequence(
				// 	&ant,
				// 	{
				// 		Action_Find{environment = &data.grid, item = objective.forage_type},
				// 		Action_Haul{environment = &data.grid, item = objective.forage_type},
				// 		Action_Return{environment = &data.grid},
				// 	},
				// )
				offset := get_random_value_f(-math.PI / 6, math.PI / 6)
				distance := get_random_value_f(4, 6)

				queue_action(
					&ant,
					Action_Walk {
						environment = &data.grid,
						walk_to = ant.pos + (rl.Vector2Rotate(ant.direction, offset) * distance),
					},
				)
			}
		}

		if tick(&ant) == .Succeeded {
			// TODO: Fetch new objective potentially
		}

		// Update timers
		ant.pheromone_time_remaining -= rl.GetFrameTime()
	}

	// Spawn ants here 
	// TODO: Remove the spawn timer and make something more flexible 
	if time.stopwatch_duration(data.timer) > ANT_SPAWN_RATE * time.Millisecond {
		inventory := &data.nest.inventory

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
		spawn_ant(data, spawn_type)

		// TODO: Move spawning of all entitys somewhere else 
		spawn_enemy(data)

		time.stopwatch_reset(&data.timer)
		time.stopwatch_start(&data.timer)
	}
}

assign_ant_new_objective :: proc(ant: ^Ant, nest: Nest) {
	new_ant_objective := roll_ant_objective(nest)
	ant.objective = new_ant_objective
}

draw_ants :: proc(data: GameData) {
	for ant in data.ants {
		draw_ant(ant)

		when ODIN_DEBUG {
			if debug_overlay {
				// Draw neighborhood 
				neighborhood := get_neighborhood(ant, data)
				defer delete(neighborhood)

				for index in neighborhood {
					pos := to_world_position(index)
					color := rl.RED
					color.a = 50
					rl.DrawRectangleV(pos, GRID_CELL_SIZE, color)
				}

				pos := get_front_block(ant) * GRID_CELL_SIZE
				color := rl.YELLOW
				color.a = 100
				rl.DrawRectangle(pos.x, pos.y, GRID_CELL_SIZE, GRID_CELL_SIZE, color)
			}
		}
	}
}

draw_entity :: proc(entity: Entity, metadata: EntityMetadata) -> bool {
	if entity.life_time < 0 {
		// Entities that haven't been born won't be drawn
		return false
	}

	color := metadata.color
	color.a = ENTITY_ALPHA

	// Lower body 
	rl.DrawCircleV(entity.pos, metadata.size / 2, color)
	// Abdomen
	rl.DrawCircleV(entity.pos + (metadata.size * entity.direction / 2), metadata.size / 4, color)
	// Head
	rl.DrawCircleV(entity.pos + (metadata.size * entity.direction), metadata.size / 3, color)

	return true
}

draw_ant :: proc(ant: Ant) {
	ant_data := AntValues[ant.type]

	if !draw_entity(ant, ant_data) {
		return
	}

	if ant.selected {
		rl.DrawCircleLinesV(ant.pos, ant_data.size, rl.WHITE)
		draw_ant_data(ant)
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

	fmt.sbprintfln(&sb, "%v", ant.type)
	ant_data := AntValues[ant.type]
	when ODIN_DEBUG {
		for i in 0 ..< sm.len(ant.actions) {
			action := sm.get(ant.actions, i)
			fmt_action(strings.to_writer(&sb), action)
		}
	} else {
		if current_action, ok := peek_current_action(ant); ok {
			fmt_action(strings.to_writer(&sb), current_action)
		}
	}

	fmt.sbprintfln(
		&sb,
		"%v\nLD: %.2f (%v)\nPH:%.2fs\n",
		ant.objective,
		ant.load,
		ant.load_type,
		ant.pheromone_time_remaining,
	)

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
