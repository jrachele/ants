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

// milliseconds
ANT_SPAWN_RATE :: 5000

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
	seek_type:                EnvironmentType,
	load_type:                EnvironmentType,
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
	spawn_cost:        f32,
}

AntPriority :: enum {
	None, // No priorities, randomly assign
	Food, // Seek honey
	Supply, // Seek wood and rock
	Defend, // Send armored and peons to danger areas to maintain order
	Attack, // Send elites to danger areas and attack
	Build, // Expand the nest, or deal with queued projects 
}

Queen :: struct {
	current_priority: AntPriority,
	priority_weight:  u8,
}

ANT_ALPHA :: 200

AntValues := [AntType]AntMetaData {
	.Peon = AntMetaData {
		size = 1,
		speed = 15,
		color = rl.BLACK,
		initial_life = -10,
		average_life = 60,
		initial_health = 5,
		carrying_capacity = 5,
		spawn_cost = 0,
	},
	.Armored = AntMetaData {
		size = 2,
		speed = 10,
		color = rl.RED,
		initial_life = -20,
		average_life = 300,
		initial_health = 100,
		carrying_capacity = 15,
		spawn_cost = 10,
	},
	.Porter = AntMetaData {
		size = 2,
		speed = 15,
		color = rl.GREEN,
		initial_life = -20,
		average_life = 300,
		initial_health = 30,
		carrying_capacity = 100,
		spawn_cost = 10,
	},
	.Elite = AntMetaData {
		size = 4,
		speed = 10,
		color = rl.BLUE,
		initial_life = -50,
		average_life = 1000,
		initial_health = 1000,
		carrying_capacity = 0,
		spawn_cost = 100,
	},
	.Queen = AntMetaData{size = 20, color = rl.DARKPURPLE, spawn_cost = 1000},
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

INVALID_BLOCK_POSITION := [2]i32{-1, -1}

Neighborhood :: struct {
	blocks:         [3]EnvironmentBlock,
	grid_positions: [3][2]i32,
}

spawn_ant :: proc(state: ^GameState, type: AntType = AntType.Peon, immediately: bool = false) {
	queen_data := AntValues[.Queen]
	ant_data := AntValues[type]
	pos :=
		QUEEN_POS +
		rl.Vector2 {
				f32(rl.GetRandomValue(-i32(queen_data.size), i32(queen_data.size))),
				f32(rl.GetRandomValue(-i32(queen_data.size), i32(queen_data.size))),
			}

	// Initially, the ants can go wherever
	direction := rl.Vector2Normalize(get_random_vec(-1, 1))

	priority := i32(state.queen.priority_weight)
	priority = clamp(priority, 0, 100)

	// Determine the ants state
	ant_state: AntState
	seek_type := EnvironmentType.Honey

	switch (state.queen.current_priority) {
	case .None:
		// Keep everything the same
		ant_state = random_select(
			[]AntState{AntState.Wander, AntState.Seek, AntState.Danger, AntState.Build},
		)
	// TODO: Create a different ant state for defending vs attacking perhaps
	case .Defend, .Attack:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_state = .Danger
		} else {
			ant_state = random_select([]AntState{AntState.Wander, AntState.Seek, AntState.Build})
		}
	case .Build:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_state = .Build
		} else {
			ant_state = random_select([]AntState{AntState.Wander, AntState.Seek, AntState.Danger})
		}
	case .Food, .Supply:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_state = .Seek
		} else {
			ant_state = random_select([]AntState{AntState.Wander, AntState.Build, AntState.Danger})
		}

		if state.queen.current_priority == .Supply {
			seek_type = random_select(
				[]EnvironmentType{EnvironmentType.Rock, EnvironmentType.Wood},
			)
		}
	}
	append(
		&state.ants,
		Ant {
			pos       = pos,
			type      = type,
			direction = direction,
			health    = ant_data.initial_health,
			life_time = immediately ? 0 : ant_data.initial_life,
			// TODO: Set default states somewhere else 
			state     = ant_state,
			seek_type = seek_type,
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
		// when ODIN_DEBUG {
		// 	ant.life_time = 0
		// }
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

		l, m, r: EnvironmentBlock = expand_values(neighborhood.blocks)
		lp, mp, rp: [2]i32 = expand_values(neighborhood.grid_positions)

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

		// TODO: Consider behavior trees since many of these states are intertwined
		#partial switch (ant.state) {
		case .Build:
			// TODO: Check if there are any build jobs, and have the ant gather build supplies 
			// seek_pheromones(&ant, neighborhood, .Build)
			set_ant_state(&ant, .Seek)
		case .Danger:
			// try_spread_pheromone(&ant, &state.grid, .General)
			// seek_pheromones(&ant, neighborhood, .Danger)
			set_ant_state(&ant, .Seek)
		case .ReturnHome:
			// If you have made it back to the ants nest, begin unloading anything if you have it
			if m.in_nest && ((m.type == ant.load_type) || (is_block_permeable(m.type))) {
				if (ant.load > 0) {
					set_ant_state(&ant, .Unload)
					break
				}
			}

			// TODO: Improve this, pheromones are not really sufficient
			seek_pheromones(&ant, neighborhood, .General)

		case .Seek:
			// Actively search for valueables 
			// TODO: Get distribution of valuables sought for from random table 
			if ant.seek_type == .Nothing {
				set_ant_state(&ant, .Wander)
				break
			}

			// If the ant is just wandering around the nest with a little bit of a load, have them drop it off
			if ant.load > 0 && (l.in_nest || r.in_nest || m.in_nest) {
				set_ant_state(&ant, .Unload)
				break
			}

			found_item := false
			// Change direction towards what is being sought 
			if (l.type == ant.seek_type && l.in_nest == false) {
				turn_ant(&ant, .Left)
				found_item = true
			} else if (r.type == ant.seek_type && r.in_nest == false) {
				turn_ant(&ant, .Right)
				found_item = true
			} else if (m.type == ant.seek_type && m.in_nest == false) {
				found_item = true
			}

			if found_item {
				set_ant_state(&ant, .Load)
				break
			}
			seek_pheromones(&ant, neighborhood, .Forage)

		case .Load:
			// If the ant is hauling, it's taking whatever block is in the middle
			if (m.amount <= 0 || m.type == .Nothing) {
				set_ant_state(&ant, .Seek)
				break
			}

			// TODO: Have ants have different loading speeds 
			ant.load_type = m.type

			// Get a mutable m block as we need to modify the grid
			m_mut := get_block_ptr(&state.grid, mp.x, mp.y)
			amount := min(ANT_LOAD_SPEED * rl.GetFrameTime(), m_mut.amount)
			ant.load += amount
			m_mut.amount -= amount

			// Set the block to nothing 
			// TODO: Probably move this to an update_grid() function along with pheromone diffusion 
			if (m_mut.amount <= 0) {
				m_mut.type = .Nothing
			}

			try_spread_pheromone(&ant, &state.grid, .General)

			// Always return home if the load is too large 
			if (ant_data.carrying_capacity != 0 && ant.load >= ant_data.carrying_capacity) {
				// It's likely that the ant wants to turn back around here,
				turn_ant(&ant, .Around)
				set_ant_state(&ant, .ReturnHome)
			}

		case .Unload:
			if (ant.load <= 0) {
				// TODO: Have the ants new state be configurable by the player/queen
				set_ant_state(&ant, .Seek)
				break
			}

			// TODO: Set amount limits on blocks 
			front_block_valid :=
				m.in_nest && (m.type == ant.load_type || (m.type == .Dirt && m.amount == 0))

			// If somehow the front block is not valid (perhaps another ), return home again 
			if !front_block_valid {
				set_ant_state(&ant, .ReturnHome)
				break
			}

			// Get a mutable m block as we need to modify the grid
			m_mut := get_block_ptr(&state.grid, mp.x, mp.y)
			if (m.type == .Dirt) {
				m_mut.amount = 0
			}
			m_mut.type = ant.load_type
			amount := min(ANT_LOAD_SPEED * rl.GetFrameTime(), ant.load)
			m_mut.amount += amount
			ant.load -= amount

			try_spread_pheromone(&ant, &state.grid, .General)
		case .Wander:
			// Continue walking in the desired direction
			try_spread_pheromone(&ant, &state.grid, .General)
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

		// Update timers
		ant.pheromone_time_remaining -= rl.GetFrameTime()
	}

	// Spawn ants here 
	// TODO: Remove the spawn timer and make something more flexible 
	if time.stopwatch_duration(state.timer) > ANT_SPAWN_RATE * time.Millisecond {
		inventory := get_inventory(state.grid)

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

		// TODO: Refactor the inventory system to avoid so much iteration
		deplete_honey(&state.grid, AntValues[spawn_type].spawn_cost)
		spawn_ant(state, spawn_type)

		time.stopwatch_reset(&state.timer)
		time.stopwatch_start(&state.timer)
	}
}

try_spread_pheromone :: proc(ant: ^Ant, grid: ^Grid, pheromone: Pheromone) -> bool {
	if ant.pheromone_time_remaining <= 0 {
		block := get_block_ptr(grid, ant.pos)
		if block != nil && block.pheromones[pheromone] != 255 {
			block.pheromones[pheromone] += 1
		}

		ant.pheromone_time_remaining = ANT_PHEROMONE_RATE + get_random_value_f(-0.5, 0.5)
		return true
	}
	return false
}

Direction :: enum {
	Forward,
	Left,
	Right,
	Around,
}
turn_ant :: proc(ant: ^Ant, direction: Direction) {
	rotation_random_offset := get_random_value_f(-0.1, 0.1)
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

seek_pheromones :: proc(ant: ^Ant, neighborhood: Neighborhood, pheromone: Pheromone) {
	direction: Direction
	most_pheromones: u8 = 0
	l, m, r := expand_values(neighborhood.blocks)
	if (l.pheromones[.Danger] > most_pheromones) {
		most_pheromones = l.pheromones[.Danger]
		direction = .Left
	} else if (m.pheromones[.Danger] > most_pheromones) {
		most_pheromones = m.pheromones[.Danger]
		direction = .Forward
	} else if (r.pheromones[.Danger] > most_pheromones) {
		most_pheromones = r.pheromones[.Danger]
		direction = .Right
	}
	turn_ant(ant, direction)
}

set_ant_state :: proc(ant: ^Ant, state: AntState) {
	if (ant.state == state) do return

	ant.prev_state = ant.state

	if (state == .Idle) {
		ant.idle_time_remaining = ANT_IDLE_TIME + get_random_value_f(-0.1, 0.1)
	}

	ant.state = state
}

get_neighborhood :: proc(ant: Ant, state: GameState) -> (Neighborhood, bool) {
	// Ray cast at -30 degrees, 0 degrees, and 30 degrees, from the ants direction vector 
	directions := [3]rl.Vector2 {
		rl.Vector2Rotate(ant.direction, -30), // Left
		ant.direction, // Middle
		rl.Vector2Rotate(ant.direction, -30), // Right
	}
	block_index := get_block_index(ant.pos)

	// FIXME: Issues with this 
	MAX_RAYCASTS :: 4
	RAY_INCREMENT :: GRID_CELL_SIZE / 6.0

	neighborhood: Neighborhood
	for i in 0 ..< 3 {
		neighborhood.grid_positions[i] = INVALID_BLOCK_POSITION
		for inc in 0 ..< MAX_RAYCASTS {
			inc := f32(inc)
			ray_position := ant.pos + (directions[i] * RAY_INCREMENT * inc)
			ray_index := get_block_index(ray_position)
			if ray_index != block_index {
				block, ok := get_block(state.grid, ray_position)
				if !ok do break
				neighborhood.grid_positions[i].x = i32(ray_position.x / GRID_CELL_SIZE)
				neighborhood.grid_positions[i].y = i32(ray_position.y / GRID_CELL_SIZE)
				neighborhood.blocks[i] = block
				break
			}
		}
	}

	return neighborhood, true
}

grid_cell_to_world_pos :: proc(x: i32, y: i32) -> rl.Vector2 {
	return rl.Vector2{f32(x) * GRID_CELL_SIZE, f32(y) * GRID_CELL_SIZE}
}

walk_ant :: proc(ant: ^Ant, neighborhood: Neighborhood) -> bool {
	ant_data := AntValues[ant.type]
	// Ensure there is nothing in the way
	l, m, r := expand_values(neighborhood.blocks)
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

	ant_color := ant_data.color
	ant_color.a = ANT_ALPHA

	if ant.life_time < 0 {
		// The ant hasn't been born yet! draw an egg instead 
		rl.DrawCircleV(ant.pos, ant_data.size, rl.WHITE)
		buf: [100]u8
		time := fmt.bprintf(buf[:], "%.fs", -ant.life_time)
		label_pos := ant.pos + {0, -ant_data.size}
		draw_text_align(
			rl.GetFontDefault(),
			time,
			i32(label_pos.x),
			i32(label_pos.y),
			.Center,
			5,
			{0, 0, 0, 100},
		)
	} else {
		// Lower body 
		rl.DrawCircleV(ant.pos, ant_data.size / 2, ant_color)
		// Abdomen
		rl.DrawCircleV(ant.pos + (ant_data.size * ant.direction / 2), ant_data.size / 4, ant_color)
		// Head
		rl.DrawCircleV(ant.pos + (ant_data.size * ant.direction), ant_data.size / 3, ant_color)

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

}

QUEEN_POS :: rl.Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2}

draw_queen :: proc() {
	queen := Ant {
		health = 100,
		type   = .Queen,
		pos    = QUEEN_POS,
	}
	draw_ant(queen)
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
