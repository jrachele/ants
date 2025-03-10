package ants

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"
import "core:time"
import rl "vendor:raylib"
Triangle :: [3]rl.Vector2

// In seconds,
ANT_AVG_LIFESPAN :: 100
ANT_PHEROMONE_RATE :: time.Second * 5
ANT_IDLE_TIME :: time.Millisecond * 300

when ODIN_DEBUG {
	ANT_SPAWN_RATE :: 1
} else {
	ANT_SPAWN_RATE :: 5
}
// One Ant every n seconds 

AntType :: enum {
	Peon,
	Armored,
	Porter,
	Elite,
	Queen,
}

Ant :: struct {
	pos:             rl.Vector2,
	direction:       rl.Vector2,
	pheromone_timer: time.Stopwatch,
	idle_timer:      time.Stopwatch,
	health:          f32,
	life_time:       f32,
	load:            f32,
	type:            AntType,
	seekType:        EnvironmentType,
	loadType:        EnvironmentType,
	state:           AntState,
	prev_state:      AntState,
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
	},
	.Armored = AntMetaData {
		size = 3,
		speed = 3,
		color = rl.RED,
		initial_life = -20,
		average_life = 300,
		initial_health = 100,
	},
	.Porter = AntMetaData {
		size = 3,
		speed = 3,
		color = rl.GREEN,
		initial_life = -20,
		average_life = 300,
		initial_health = 30,
	},
	.Elite = AntMetaData {
		size = 15,
		speed = 10,
		color = rl.BLUE,
		initial_life = -50,
		average_life = 1000,
		initial_health = 1000,
	},
	.Queen = AntMetaData{size = 30, color = rl.DARKPURPLE},
}

AntState :: enum {
	Wander, // This is either patrol, or search
	Danger, // Whether or not the ant engages depends on the situation
	Seek, // Seeking wood, dirty, rocks, food, etc.
	Haul, // Actively begin hauling the resource 
	Build, // Building planned projects 
	Idling, // Waiting for a second and analyzing the environment
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
	timer: time.Stopwatch
	time.stopwatch_start(&timer)
	append(
		ants,
		Ant {
			pos = pos,
			type = type,
			direction = direction,
			health = ant_data.initial_health,
			life_time = ant_data.initial_life,
			pheromone_timer = timer,
		},
	)
}

update_ants :: proc(state: ^GameState) {
	// Make a decision for the ant based on its role 
	for &ant, i in state.ants {
		ant.life_time += rl.GetFrameTime()
		ant_data := AntValues[ant.type]
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

		neighborhood := get_neighborhood(ant, state^)
		l, m, r: ^EnvironmentBlock = expand_values(neighborhood)
		// Avoid all impermeable objects 
		if m != nil && !is_block_permeable(m.type) {
			// The ant's gotta pause for a sec 
			set_ant_state(&ant, .Idling)

			rotation_random_offset := get_random_value_f(-10, 10)
			if l != nil && !is_block_permeable(l.type) && r != nil && !is_block_permeable(r.type) {
				// If the entire way forward is full of rocks, rotate the entire direction 90 degrees 
				right := bool(rl.GetRandomValue(0, 1))
				if right {
					ant.direction = rl.Vector2Rotate(ant.direction, 90 + rotation_random_offset)
				} else {
					ant.direction = rl.Vector2Rotate(ant.direction, -90 + rotation_random_offset)
				}
			} else if l != nil && !is_block_permeable(l.type) {
				ant.direction = rl.Vector2Rotate(ant.direction, 30 + rotation_random_offset)
			} else {
				ant.direction = rl.Vector2Rotate(ant.direction, -30 + rotation_random_offset)
			}
		}


		#partial switch (ant.state) {
		case .Seek:
			// Actively search for valueables 
			// TODO: Get distribution of valuables sought for from random table 
			if ant.seekType == .Nothing {
				ant.state = .Idling
				break
			}

			fallthrough
		case .Wander:
			// Continue walking in the desired direction
			ant.direction = rl.Vector2Normalize(ant.direction + get_random_vec(-0.05, 0.05))
			random_walk(&ant)
		case .Idling:
			// Kinda spin around aimlessly.
			ant.direction = rl.Vector2Normalize(ant.direction + get_random_vec(-0.05, 0.05))
			if time.stopwatch_duration(ant.idle_timer) > ANT_IDLE_TIME {
				set_ant_state(&ant, ant.prev_state)
			}
		}

		//block_index := ant.pos / GRID_CELL_SIZE

		// Ant pheromone drop
		if time.stopwatch_duration(ant.pheromone_timer) > ANT_PHEROMONE_RATE {
			time.stopwatch_reset(&ant.pheromone_timer)
			time.stopwatch_start(&ant.pheromone_timer)

			block := get_block(state.grid[:], ant.pos)
			if (block != nil && block.pheromones[.General] != 255) {
				block.pheromones[.General] += 1
			}
		}
	}
}

set_ant_state :: proc(ant: ^Ant, state: AntState) {
	if (ant.state == state) do return

	ant.prev_state = ant.state

	if (state == .Idling) {
		time.stopwatch_reset(&ant.idle_timer)
		time.stopwatch_start(&ant.idle_timer)
	} else {
		time.stopwatch_reset(&ant.idle_timer)
	}

	ant.state = state
}

get_neighborhood :: proc(ant: Ant, state: GameState) -> [3]^EnvironmentBlock {
	// Ray cast at -30 degrees, 0 degrees, and 30 degrees, from the ants direction vector 
	left_direction := rl.Vector2Rotate(ant.direction, -30) * 0.5
	right_direction := rl.Vector2Rotate(ant.direction, -30) * 0.5
	middle_direction := ant.direction * 0.5
	block_index := ant.pos / GRID_CELL_SIZE
	ant_block := get_block(state.grid[:], ant.pos)

	left_block, middle_block, right_block := ant_block, ant_block, ant_block

	for left_block == ant_block {
		left_block = get_block(state.grid[:], ant.pos + left_direction)
		left_direction *= 2
	}
	for middle_block == ant_block {
		middle_block = get_block(state.grid[:], ant.pos + middle_direction)
		middle_direction *= 2
	}
	for right_block == ant_block {
		right_block = get_block(state.grid[:], ant.pos + right_direction)
		right_direction *= 2
	}
	return {left_block, middle_block, right_block}
}

grid_cell_to_world_pos :: proc(x: i32, y: i32) -> rl.Vector2 {
	return rl.Vector2{f32(x) * GRID_CELL_SIZE, f32(y) * GRID_CELL_SIZE}
}

random_walk :: proc(ant: ^Ant) {
	ant_data := AntValues[ant.type]
	ant.pos += ant.direction * rl.GetFrameTime() * ant_data.speed
}

draw_ants :: proc(ants: []Ant) {
	for ant in ants {
		draw_ant(ant)

		mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

		ant_data := AntValues[ant.type]
		if rl.Vector2Distance(mouse_pos, ant.pos) < ant_data.size {
			draw_ant_data(ant)
		}
	}
}

// For now just draw triangles 
draw_ant :: proc(ant: Ant) {
	ant_data := AntValues[ant.type]
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
	}

	when ODIN_DEBUG {
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
		fmt.sbprintf(&sb, "%v (%.2fs)", ant.type, ant.life_time * -1.0)
	} else {
		fmt.sbprintf(&sb, "%v", ant.type)
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
		rl.Color{0, 0, 0, 80},
	)

}
