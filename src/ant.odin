package ants

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

ANT_LOAD_SPEED :: 2
ANT_AVG_LIFESPAN :: 100
ANT_PHEROMONE_RATE :: 0.5
ANT_IDLE_TIME :: 0.300

when ODIN_DEBUG {
	// One Ant every n milliseconds 
	ANT_SPAWN_RATE :: 100
} else {
	ANT_SPAWN_RATE :: 5000
}

AntType :: enum {
	Peon,
	Armored,
	Porter,
	Elite,
	Queen,
}

Ant :: struct {
	pos:                      rl.Vector2,
	direction:                rl.Vector2,
	pheromone_time_remaining: f32,
	idle_time_remaining:      f32,
	health:                   f32,
	life_time:                f32,
	load:                     f32,
	type:                     AntType,
	seekType:                 EnvironmentType,
	loadType:                 EnvironmentType,
	state:                    AntState,
	prev_state:               AntState,
	selected:                 bool,
}

AntMetaData :: struct {
	color:             rl.Color,
	size:              f32,
	speed:             f32,
	initial_life:      f32, // Initial life stage when spawned 
	average_life:      f32, // Average life stage until health deteriorates 
	initial_health:    f32,
	carrying_capacity: f32,
}

AntValues := [AntType]AntMetaData {
	.Peon = AntMetaData {
		size = 1,
		speed = 10,
		color = rl.BLACK,
		initial_life = -10,
		average_life = 60,
		initial_health = 5,
		carrying_capacity = 5,
	},
	.Armored = AntMetaData {
		size = 3,
		speed = 3,
		color = rl.RED,
		initial_life = -20,
		average_life = 300,
		initial_health = 100,
		carrying_capacity = 15,
	},
	.Porter = AntMetaData {
		size = 3,
		speed = 3,
		color = rl.GREEN,
		initial_life = -20,
		average_life = 300,
		initial_health = 30,
		carrying_capacity = 100,
	},
	.Elite = AntMetaData {
		size = 15,
		speed = 10,
		color = rl.BLUE,
		initial_life = -50,
		average_life = 1000,
		initial_health = 1000,
		carrying_capacity = 0,
	},
	.Queen = AntMetaData{size = 30, color = rl.DARKPURPLE},
}

AntState :: enum {
	Wander, // This is either patrol, or search
	Idle, // Waiting for a second and analyzing the environment
	Danger, // Whether or not the ant engages depends on the situation
	Seek, // Seeking wood, dirty, rocks, food, etc.
	Load, // Actively begin hauling the resource 
	Unload, // Unloading resources
	Build, // Building planned projects 
	ReturnHome, // Returning to the queen
}

spawn_ant :: proc(queen: Ant, ants: ^[dynamic]Ant, type: AntType = AntType.Peon) {
	queen_data := AntValues[.Queen]
	ant_data := AntValues[type]
	pos :=
		queen.pos +
		rl.Vector2 {
				f32(rl.GetRandomValue(-i32(queen_data.size), i32(queen_data.size))),
				f32(rl.GetRandomValue(-i32(queen_data.size), i32(queen_data.size))),
			}

	// Initially, the ants can go wherever
	direction := rl.Vector2Normalize(get_random_vec(-1, 1))
	append(
		ants,
		Ant {
			pos       = pos,
			type      = type,
			direction = direction,
			health    = ant_data.initial_health,
			life_time = ant_data.initial_life,
			// TODO: Set default states somewhere else 
			state     = .Seek,
			seekType  = .Honey,
		},
	)
}

update_ants :: proc(state: ^GameState) {
	mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	for &ant in state.ants {
		ant_data := AntValues[ant.type]
		ant.selected = rl.Vector2Distance(mouse_pos, ant.pos) < ant_data.size
	}

	if state.paused do return

	for &ant, i in state.ants {
		ant_data := AntValues[ant.type]

		ant.life_time += rl.GetFrameTime()
		when ODIN_DEBUG {
			ant.life_time = 0
		}
		if (ant.life_time < 0) do continue
		if (ant.life_time > ant_data.average_life) {
			ant.health -= rl.GetFrameTime()
		}

		if (ant.health < 0) {
			ordered_remove(&state.ants, i)
			continue
		}

		neighborhood, ok := get_neighborhood(ant, state^)
		if !ok {
			// The ant is in an impossible state!, remove it
			ordered_remove(&state.ants, i)
			continue
		}

		l, m, r: EnvironmentBlock = expand_values(neighborhood)

		// Always return home if the load is too large 
		if (ant_data.carrying_capacity != 0 &&
			   ant.load >= ant_data.carrying_capacity &&
			   ant.state != .ReturnHome) {
			set_ant_state(&ant, .ReturnHome)
		}

		// Begin walking the ant if it's in any state other than idling, hauling, or building,
		// TODO: This needs a refactor 
		if ant.state != .Idle &&
		   ant.state != .Load &&
		   ant.state != .Build &&
		   ant.state != .Unload {
			if !walk_ant(&ant, neighborhood) {
				// The ant's gotta pause for a sec
				set_ant_state(&ant, .Idle)
			}
		}

		#partial switch (ant.state) {
		case .ReturnHome:
			// If you have made it back to the ants nest, begin unloading anything if you have it
			if m.in_nest && ((m.type == ant.loadType) || (is_block_permeable(m.type))) {
				if (ant.load > 0) {
					set_ant_state(&ant, .Unload)
					break
				}
			}

			direction: Direction
			most_pheromones: u8 = 0
			if (l.pheromones[.General] > most_pheromones) {
				most_pheromones = l.pheromones[.General]
				direction = .Left
			} else if (m.pheromones[.General] > most_pheromones) {
				most_pheromones = m.pheromones[.General]
				direction = .Forward
			} else if (r.pheromones[.General] > most_pheromones) {
				most_pheromones = r.pheromones[.General]
				direction = .Right
			}
			turn_ant(&ant, direction)

		case .Seek:
			// Actively search for valueables 
			// TODO: Get distribution of valuables sought for from random table 
			if ant.seekType == .Nothing {
				set_ant_state(&ant, .Wander)
				break
			}

			found_item := false
			// Change direction towards what is being sought 
			if (l.type == ant.seekType) {
				turn_ant(&ant, .Left)
				found_item = true
			} else if (r.type == ant.seekType) {
				turn_ant(&ant, .Right)
				found_item = true
			} else if (m.type == ant.seekType) {
				found_item = true
			}

			if found_item {
				set_ant_state(&ant, .Load)
				break
			}

			turn_ant(&ant, .Forward)

		case .Load:
			// If the ant is hauling, it's taking whatever block is in the middle
			if (m.amount <= 0 || m.type == .Nothing) {
				set_ant_state(&ant, .Seek)
				break
			}

			// TODO: Have ants have different loading speeds 
			ant.loadType = m.type
			amount := min(ANT_LOAD_SPEED * rl.GetFrameTime(), m.amount)
			ant.load += amount
			m.amount -= amount

			// Set the block to nothing 
			// TODO: Probably move this to an update_grid() function along with pheromone diffusion 
			if (m.amount <= 0) {
				m.type = .Nothing
			}
		case .Unload:
			if (ant.load <= 0) {
				// TODO: Have the ants new state be configurable by the player/queen
				set_ant_state(&ant, .Wander)
				break
			}

			// TODO: Set amount limits on blocks 
			front_block_valid :=
				m.in_nest && (m.type == ant.loadType || (m.type == .Dirt && m.amount == 0))

			// If somehow the front block is not valid (perhaps another ), return home again 
			if !front_block_valid {
				set_ant_state(&ant, .ReturnHome)
				break
			}

			if (m.type == .Dirt) {
				m.amount = 0
			}
			m.type = ant.loadType
			amount := min(ANT_LOAD_SPEED * rl.GetFrameTime(), ant.load)
			m.amount += amount
			ant.load -= amount
		case .Wander:
			// Continue walking in the desired direction
			turn_ant(&ant, .Forward)
		case .Idle:
			// Kinda spin around aimlessly.
			turn_ant(&ant, .Forward)
			ant.idle_time_remaining -= rl.GetFrameTime()

			// If it's time to stop idling, make sure we can get around obstacles 
			if (ant.idle_time_remaining <= 0) {
				// Avoid setting the ant to its previous state if it was somehow idling 
				if (ant.prev_state == .Idle) {
					set_ant_state(&ant, .Wander)
				} else {
					set_ant_state(&ant, ant.prev_state)
				}
			}
		}

		// Ant pheromone drop if venturing
		if ant.state == .Seek || ant.state == .Wander {
			if ant.pheromone_time_remaining <= 0 {
				block := get_block_ptr(&state.grid, ant.pos)
				if block != nil && block.pheromones[.General] != 255 {
					block.pheromones[.General] += 1
				}

				ant.pheromone_time_remaining = ANT_PHEROMONE_RATE + get_random_value_f(-0.5, 0.5)
			}
		}

		ant.pheromone_time_remaining -= rl.GetFrameTime()
	}

	// Spawn ants here 
	if time.stopwatch_duration(state.timer) > ANT_SPAWN_RATE * time.Millisecond {
		// TODO: Spawn more than peons
		spawn_ant(state.queen, &state.ants)
		time.stopwatch_reset(&state.timer)
		time.stopwatch_start(&state.timer)
	}
}

Direction :: enum {
	Forward,
	Left,
	Right,
	Around,
}
turn_ant :: proc(ant: ^Ant, direction: Direction) {
	rotation_random_offset := get_random_value_f(-0.25, 0.25)
	switch (direction) {
	case .Left:
		ant.direction = rl.Vector2Rotate(ant.direction, -30 + rotation_random_offset)
	case .Right:
		ant.direction = rl.Vector2Rotate(ant.direction, 30 + rotation_random_offset)
	case .Forward:
		ant.direction = rl.Vector2Rotate(ant.direction, rotation_random_offset)
	case .Around:
		right := bool(rl.GetRandomValue(0, 1))
		if right {
			ant.direction = rl.Vector2Rotate(ant.direction, 90 + rotation_random_offset)
		} else {
			ant.direction = rl.Vector2Rotate(ant.direction, -90 + rotation_random_offset)
		}
	}
}

set_ant_state :: proc(ant: ^Ant, state: AntState) {
	if (ant.state == state) do return

	ant.prev_state = ant.state

	if (state == .Idle) {
		ant.idle_time_remaining = ANT_IDLE_TIME + get_random_value_f(-0.1, 0.1)
	}

	ant.state = state
}

get_neighborhood :: proc(ant: Ant, state: GameState) -> ([3]EnvironmentBlock, bool) {
	// Ray cast at -30 degrees, 0 degrees, and 30 degrees, from the ants direction vector 
	// FIXME: This is not working properly, the ants stop way far away from the obstacle 
	left_direction := rl.Vector2Rotate(ant.direction, -30) * 0.01
	right_direction := rl.Vector2Rotate(ant.direction, -30) * 0.01
	middle_direction := ant.direction * 0.01
	block_index := ant.pos / GRID_CELL_SIZE
	ant_block, ok := get_block(state.grid, ant.pos)

	if !ok do return {}, false

	left_block, middle_block, right_block := ant_block, ant_block, ant_block

	for left_block == ant_block {
		left_block, ok = get_block(state.grid, ant.pos + left_direction)
		if !ok do break
		left_direction *= 2
	}
	for middle_block == ant_block {
		middle_block, ok = get_block(state.grid, ant.pos + middle_direction)
		if !ok do break
		middle_direction *= 2
	}
	for right_block == ant_block {
		right_block, ok = get_block(state.grid, ant.pos + right_direction)
		if !ok do break
		right_direction *= 2
	}
	return {left_block, middle_block, right_block}, true
}

grid_cell_to_world_pos :: proc(x: i32, y: i32) -> rl.Vector2 {
	return rl.Vector2{f32(x) * GRID_CELL_SIZE, f32(y) * GRID_CELL_SIZE}
}

walk_ant :: proc(ant: ^Ant, neighborhood: [3]EnvironmentBlock) -> bool {
	ant_data := AntValues[ant.type]
	// Ensure there is nothing in the way
	l, m, r := expand_values(neighborhood)
	// Move forward if we're good 
	if is_block_permeable(m.type) {
		ant.pos += ant.direction * rl.GetFrameTime() * ant_data.speed
		return true
	}

	// Otherwise make adjustments and try to walk on the next frame 
	if !is_block_permeable(l.type) && !is_block_permeable(r.type) {
		// If the entire way forward is full of rocks, rotate the entire direction 90 degrees 
		turn_ant(ant, .Around)
	} else if !is_block_permeable(l.type) {
		turn_ant(ant, .Right)
	} else {
		turn_ant(ant, .Left)
	}

	return false
}

draw_ants :: proc(ants: []Ant) {
	for ant in ants {
		draw_ant(ant)
	}
}

// For now just draw triangles 
draw_ant :: proc(ant: Ant) {
	ant_data := AntValues[ant.type]
	if ant.selected {
		rl.DrawCircleLinesV(ant.pos, ant_data.size, rl.WHITE)
	}

	if ant.life_time < 0 {
		// The ant hasn't been born yet! draw an egg instead 
		rl.DrawCircleV(ant.pos, ant_data.size, rl.WHITE)
	} else {
		// Lower body 
		rl.DrawCircleV(ant.pos, ant_data.size / 2, ant_data.color)
		// Abdomen
		rl.DrawCircleV(ant.pos + (ant.direction / 2), ant_data.size / 4, ant_data.color)
		// Head
		rl.DrawCircleV(ant.pos + ant.direction, ant_data.size / 3, ant_data.color)

		// Load if any
		if (ant.load > 0) {
			block_color := get_block_color(ant.loadType)
			rl.DrawCircleV(ant.pos + (ant.direction * 2), ant_data.size / 4, block_color)
		}
	}

}

draw_queen :: proc(ant: Ant) {
	// If the queen dies, eventually a knight can take her place 
	ant_data := AntValues[ant.type]

	rl.DrawPoly(ant.pos, 7, ant_data.size, 0, ant_data.color)
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
