package ants

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

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
}

Ant :: struct {
	pos:                      rl.Vector2,
	direction:                rl.Vector2,
	// neighborhood:             Neighborhood,
	pheromone_time_remaining: f32,
	health:                   f32,
	life_time:                f32,
	load:                     f32,
	load_type:                EnvironmentType,
	type:                     AntType,
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
	load_speed:        f32,
}

AntPriority :: enum {
	None, // No priorities, randomly assign
	Food, // Seek honey
	Supply, // Seek wood and rock
	Defend, // Send armored and peons to danger areas to maintain order
	Attack, // Send elites to danger areas and attack
	Build, // Expand the nest, or deal with queued projects 
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
		load_speed = 2,
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
		load_speed = 5,
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
		load_speed = 20,
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
		load_speed = 0,
	},
}


AntState_Wander :: struct {}
AntState_Idle :: struct {
	idle_time_remaining: f32,
}
AntState_Danger :: struct {
	fleeing: bool,
}
AntState_Seek :: struct {
	seek_type: EnvironmentType,
}
AntState_Load :: struct {}
AntState_Unload :: struct {}
AntState_Build :: struct {}
AntState_ReturnHome :: struct {}

AntState :: union {
	AntState_Wander, // This is either patrol, or search
	AntState_Idle, // Waiting for a second and analyzing the environment
	AntState_Danger, // Whether or not the ant engages depends on the situation
	AntState_Seek, // Seeking wood, dirty, rocks, food, etc.
	AntState_Load, // Actively begin hauling the resource 
	AntState_Unload, // Unloading resources
	AntState_Build, // Building planned projects 
	AntState_ReturnHome, // Returning to the queen
}

INVALID_BLOCK_POSITION := [2]i32{-1, -1}

// Store a set of block indices 
Neighborhood :: map[i32]struct {}

init_ant :: proc(type: AntType, nest: Nest, allocator := context.allocator) -> (ant: Ant) {
	ant_data := AntValues[type]
	ant.pos = NEST_POS
	// Initially, the ants can go wherever
	ant.direction = rl.Vector2Normalize(get_random_vec(-1, 1))
	ant.type = type
	ant.health = ant_data.initial_health
	ant.life_time = ant_data.initial_life
	ant.state = ant_state_from_nest(nest)
	return
}

// deinit_ant :: proc(ant: ^Ant) {
// 	delete(&ant.neighborhood)
// }

spawn_ant :: proc(
	state: ^GameState,
	type: AntType = AntType.Peon,
	immediately: bool = false,
	allocator := context.allocator,
) {
	ant := init_ant(type, state.nest, allocator)
	if immediately {
		ant.life_time = 0
	}

	append(&state.ants, ant)
}

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

		neighborhood := get_neighborhood(ant, state^)
		defer delete(neighborhood)

		if len(neighborhood) == 0 {
			// The ant is in an impossible state!, remove it
			ordered_remove(&state.ants, i)
			continue
		}

		// Pre-move the ant then run through the states
		switch (reflect.union_variant_typeid(ant.state)) {
		case AntState_Build, AntState_Idle, AntState_Load, AntState_Unload:
		// Do not pre-move here 
		case:
			if !walk_ant(&ant, state.grid) {
				// The ant's gotta pause for a sec
				set_ant_state(&ant, AntState_Idle{})
			}
		}

		switch &ant_state in ant.state {
		case AntState_Build:
			// TODO: Check if there are any build jobs, and have the ant gather build supplies 
			// seek_pheromones(&ant, neighborhood, .Build)
			set_ant_state(&ant, AntState_Seek{seek_type = .Honey})

		case AntState_Danger:
			// try_spread_pheromone(&ant, &state.grid, .General)
			// seek_pheromones(&ant, neighborhood, .Danger)
			set_ant_state(&ant, AntState_Seek{seek_type = .Honey})
		case AntState_ReturnHome:
			// If you have made it back to the ants nest, begin unloading anything if you have it
			if is_in_nest(ant) && ant.load > 0 {
				set_ant_state(&ant, AntState_Unload{})
				break
			}

			if ant.load > 0 {
				try_spread_pheromone(&ant, &state.grid, .Forage)
			}

			// TODO: Fix direction lock-on
			turn_ant(&ant, rl.Vector2Normalize(NEST_POS - ant.pos))
			seek_pheromones(&ant, neighborhood, state.grid, .General)

		case AntState_Seek:
			// Actively search for valueables 
			if ant_state.seek_type == .Nothing {
				set_ant_state(&ant, AntState_Wander{})
				break
			}

			seek_item(&ant, neighborhood, state.grid, ant_state.seek_type)

			_, m_pos, _ := expand_values(get_immediate_neighborhood(ant))
			block, _ := get_block(state.grid, expand_values(m_pos))

			if block.type == ant_state.seek_type {
				set_ant_state(&ant, AntState_Load{})
				break
			}
			seek_pheromones(&ant, neighborhood, state.grid, .Forage)
			try_spread_pheromone(&ant, &state.grid, .General)

		case AntState_Load:
			_, m_pos, _ := expand_values(get_immediate_neighborhood(ant))
			block := get_block_ptr(&state.grid, expand_values(m_pos))

			// If the ant is hauling, it's taking whatever block is in the middle
			if (block.amount <= 0 || block.type == .Nothing) {
				set_ant_state(&ant, AntState_Seek{seek_type = ant.load_type})
				break
			}

			ant.load_type = block.type

			// Get a mutable m block as we need to modify the grid
			amount := min(ant_data.load_speed * rl.GetFrameTime(), block.amount)
			ant.load += amount
			block.amount -= amount

			try_spread_pheromone(&ant, &state.grid, .Forage)

			// Always return home if the load is too large 
			if (ant_data.carrying_capacity != 0 && ant.load >= ant_data.carrying_capacity) {
				// It's likely that the ant wants to turn back around here,
				turn_ant(&ant, Direction.Around)
				set_ant_state(&ant, AntState_ReturnHome{})
			}

		case AntState_Unload:
			if (ant.load <= 0) {
				assign_ant_new_state(&ant, state.nest)
				break
			}

			amount := min(ant_data.load_speed * rl.GetFrameTime(), ant.load)
			state.nest.inventory[ant.load_type] += amount
			ant.load -= amount

			try_spread_pheromone(&ant, &state.grid, .General)
		case AntState_Wander:
			// Continue walking in the desired direction
			try_spread_pheromone(&ant, &state.grid, .General)
			turn_ant(&ant, Direction.Forward)
		case AntState_Idle:
			// Kinda spin around aimlessly.
			turn_ant(&ant, Direction.Forward)
			ant_state.idle_time_remaining -= rl.GetFrameTime()

			// If it's time to stop idling, make sure we can get around obstacles 
			if (ant_state.idle_time_remaining <= 0) {
				// Avoid setting the ant to its previous state if it was somehow idling 
				_, prev_idle := ant.prev_state.(AntState_Idle)
				if (prev_idle) {
					set_ant_state(&ant, AntState_Wander{})
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

		time.stopwatch_reset(&state.timer)
		time.stopwatch_start(&state.timer)
	}
}

assign_ant_new_state :: proc(ant: ^Ant, nest: Nest) {
	new_ant_state := ant_state_from_nest(nest)
	set_ant_state(ant, new_ant_state)
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

turn_ant :: proc {
	turn_ant_direction,
	turn_ant_v2,
}

SLIGHT_TURN :: math.PI / 6
HARD_TURN :: math.PI / 2

turn_ant_direction :: proc(ant: ^Ant, direction: Direction) {
	rotation_random_offset := get_random_value_f(-0.05, 0.05)
	switch (direction) {
	case .Left:
		ant.direction = rl.Vector2Rotate(ant.direction, -SLIGHT_TURN + rotation_random_offset)
	case .Right:
		ant.direction = rl.Vector2Rotate(ant.direction, SLIGHT_TURN + rotation_random_offset)
	case .Forward:
		ant.direction = rl.Vector2Rotate(ant.direction, rotation_random_offset)
	case .Around:
		left := bool(rl.GetRandomValue(0, 1))
		if left {
			ant.direction = rl.Vector2Rotate(ant.direction, -HARD_TURN + rotation_random_offset)
		} else {
			ant.direction = rl.Vector2Rotate(ant.direction, HARD_TURN + rotation_random_offset)
		}
	}
}

turn_ant_v2 :: proc(ant: ^Ant, direction: rl.Vector2) {
	rotation_random_offset := get_random_value_f(-0.05, 0.05)
	ant.direction = rl.Vector2Rotate(direction, rotation_random_offset)
}

seek_item :: proc(
	ant: ^Ant,
	neighborhood: Neighborhood,
	grid: Grid,
	block_type: EnvironmentType,
) -> bool {
	best_index: i32 = -1
	best_distance: f32
	for index in neighborhood {
		block, _ := get_block(grid, int(index))
		if block.type == block_type {
			block_position := get_world_position_from_block_index(index)
			block_distance := rl.Vector2Distance(ant.pos, block_position)
			if best_index == -1 || block_distance < best_distance {
				best_index = index
				best_distance = block_distance
			}
		}
	}

	if best_index == -1 {
		return false
	}


	// TODO: Use A* or something?
	desired_world_position := get_world_position_from_block_index(best_index)
	turn_ant(ant, rl.Vector2Normalize(desired_world_position - ant.pos))

	return true
}

get_world_position_from_block_index :: proc(index: i32) -> rl.Vector2 {
	grid_position := Grid_Cell_Position{index % GRID_WIDTH, index / GRID_WIDTH}
	return rl.Vector2{f32(grid_position.x), f32(grid_position.y)} * GRID_CELL_SIZE
}

seek_pheromones :: proc(ant: ^Ant, neighborhood: Neighborhood, grid: Grid, pheromone: Pheromone) {
	most_pheromones: u8 = 0
	best_index: i32 = -1
	for index in neighborhood {
		block, _ := get_block(grid, int(index))
		pheromones_on_block := block.pheromones[pheromone]
		if pheromones_on_block > most_pheromones {
			most_pheromones = pheromones_on_block
			best_index = index
		}
	}

	if best_index == -1 {
		return
	}

	desired_world_position := get_world_position_from_block_index(best_index)

	// TODO: Use A* or something?
	turn_ant(ant, rl.Vector2Normalize(desired_world_position - ant.pos))
}

set_ant_state :: proc(ant: ^Ant, state: AntState) {
	if (ant.state == state) do return

	ant.prev_state = ant.state

	// If we are setting the state to an idle state, set a proper default idle_time_remaining
	idle_state, ok := state.(AntState_Idle)
	if (ok) {
		if idle_state.idle_time_remaining == 0 {
			idle_state.idle_time_remaining = ANT_IDLE_TIME + get_random_value_f(-0.1, 0.1)
		}
	}

	ant.state = state
}

Grid_Cell_Position :: [2]i32

// This is in block sizes
DEFAULT_SEARCH_RADIUS :: 40
DEFAULT_NUM_RAYS :: 10
RAY_INCREMENT :: GRID_CELL_SIZE / 6.0

get_neighborhood :: proc(
	ant: Ant,
	state: GameState,
	radius: f32 = DEFAULT_SEARCH_RADIUS,
	cone_degrees: f32 = 150, // 360 here would be full vision
) -> (
	neighborhood: Neighborhood,
) {

	origin_block_index := get_block_index(ant.pos)

	for i in 0 ..< DEFAULT_NUM_RAYS {
		angle := f32(i) * (cone_degrees / DEFAULT_NUM_RAYS) - (cone_degrees / 2)
		direction := rl.Vector2Normalize(rl.Vector2Rotate(ant.direction, math.to_radians(angle)))

		ray_position := ant.pos + (direction * RAY_INCREMENT)
		distance: f32 = 0
		for distance < DEFAULT_SEARCH_RADIUS {
			ray_block_index := get_block_index(ray_position)
			// TODO: Use a real raycasting algorithm that does not rely on pure naive chance... after the jam...
			// Add all blocks touched by the ray in the set
			if origin_block_index != ray_block_index {
				neighborhood[ray_block_index] = {}
			}
			distance = rl.Vector2Distance(ant.pos, ray_position)
			ray_position += (direction * RAY_INCREMENT)
		}

		when ODIN_DEBUG {
			if debug_overlay {
				rl.DrawLineV(ant.pos, ray_position, rl.PINK)
			}
		}
	}

	return
}

// This gets the blocks on the left, in the middle, and to the right of the ant, at 30 degree angle offsets, in that order 
get_immediate_neighborhood :: proc(ant: Ant) -> (grid_positions: [3]Grid_Cell_Position) {
	origin_block_index := get_block_index(ant.pos)
	directions := [3]rl.Vector2 {
		rl.Vector2Rotate(ant.direction, -math.PI / 6),
		ant.direction,
		rl.Vector2Rotate(ant.direction, math.PI / 6),
	}

	for dir, i in directions {
		distance: f32 = 0
		ray_position := ant.pos + (dir * RAY_INCREMENT)
		ray_block_index := get_block_index(ray_position)
		for ray_block_index == origin_block_index {
			ray_position += (dir * RAY_INCREMENT)
			ray_block_index = get_block_index(ray_position)
		}
		grid_positions[i] = {
			i32(ray_position.x / GRID_CELL_SIZE),
			i32(ray_position.y / GRID_CELL_SIZE),
		}
	}

	return
}

walk_ant :: proc(ant: ^Ant, grid: Grid) -> bool {
	ant_data := AntValues[ant.type]

	// Ensure there is nothing in the way
	lp, mp, rp := expand_values(get_immediate_neighborhood(ant^))
	l, l_real := get_block(grid, expand_values(lp))
	m, m_real := get_block(grid, expand_values(mp))
	r, r_real := get_block(grid, expand_values(rp))

	// Move forward if we're good 
	if m_real && is_block_permeable(m.type) {
		ant.pos += ant.direction * rl.GetFrameTime() * ant_data.speed
		return true
	}

	// Otherwise make adjustments and try to walk on the next frame 
	if (!l_real || !is_block_permeable(l.type)) && (!r_real || !is_block_permeable(r.type)) {
		// If the entire way forward is full of rocks, rotate the entire direction 90 degrees 
		turn_ant(ant, Direction.Around)
	} else if (!l_real || !is_block_permeable(l.type)) {
		turn_ant(ant, Direction.Right)
	} else {
		turn_ant(ant, Direction.Left)
	}

	return false
}

// init_ants :: proc() -> [dynamic]Ant {
// 	return make([dynamic]Ant)
// }

// deinit_ants :: proc(ants: ^[dynamic]Ant) {
// 	for &ant in ants {
// 		deinit_ant(&ant)
// 	}

// 	free(ants)
// }

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
					color.a = 150
					rl.DrawRectangleV(pos, GRID_CELL_SIZE, color)
				}
			}
		}
	}
}

// For now just draw triangles 
draw_ant :: proc(ant: Ant) {
	if ant.life_time < 0 {
		// Ants that haven't been born won't be drawn
		return
	}

	ant_data := AntValues[ant.type]
	if ant.selected {
		rl.DrawCircleLinesV(ant.pos, ant_data.size, rl.WHITE)
	}

	ant_color := ant_data.color
	ant_color.a = ANT_ALPHA

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
