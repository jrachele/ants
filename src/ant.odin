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

Walkable :: struct {
	pos:       rl.Vector2,
	direction: rl.Vector2,
	speed:     f32,
	health:    f32,
	life_time: f32,
}

Ant :: struct {
	using walkable:           Walkable,
	pheromone_time_remaining: f32,
	load:                     f32,
	load_type:                EnvironmentType,
	type:                     AntType,
	state:                    AntState,
	objective:                AntObjective,
	selected:                 bool,
}

Enemy :: struct {
	using walkable: Walkable,
}

AntMetaData :: struct {
	color:             rl.Color,
	size:              f32,
	initial_speed:     f32,
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
		initial_speed = 15,
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
		initial_speed = 10,
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
		initial_speed = 15,
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

		// Handle ant states
		switch &ant_state in ant.state {
		case AntState_Walk:
			if rl.Vector2Distance(ant_state.target_pos, ant.pos) <=
			   min((GRID_CELL_SIZE / 2), ant_data.size) {
				// If the ant has reached the target position, idle
				set_ant_state(&ant, AntState_Idle{})
				break
			}

			turn_ant(&ant, Direction.Forward)

			// Lock the direction back in if the ant has strayed too far away from the target position
			direction := rl.Vector2Normalize(ant_state.target_pos - ant.pos)
			if abs(rl.Vector2Angle(ant.direction, direction)) > math.PI / 4 {
				turn_ant(&ant, direction)
			}

			// If the ant was unable to walk due to an obstacle, idle
			if !walk_ant(&ant, state.grid) {
				set_ant_state(&ant, AntState_Idle{})
			}

		case AntState_Fight:
		// TODO: turn towards enemy, and if close enough attack 
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
					turn_ant(&ant, Direction.Right)
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

		time.stopwatch_reset(&state.timer)
		time.stopwatch_start(&state.timer)
	}
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
	rotation_random_offset := get_random_value_f(-0.1, 0.1)
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

find_item :: proc(
	ant: ^Ant,
	neighborhood: Neighborhood,
	grid: Grid,
	block_type: EnvironmentType,
) -> rl.Vector2 {
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
		return {-1, -1}
	}

	return get_world_position_from_block_index(best_index)
}

// Any blocks with a pheromone count below this will not be considered by the ant 
PHEROMONE_SEEK_THRESHOLD :: 10
find_most_pheromones :: proc(
	ant: ^Ant,
	neighborhood: Neighborhood,
	grid: Grid,
	pheromone: Pheromone,
) -> rl.Vector2 {
	most_pheromones: f32 = 0
	best_index: i32 = -1
	for index in neighborhood {
		block, _ := get_block(grid, int(index))
		pheromones_on_block := block.pheromones[pheromone]
		if pheromones_on_block > most_pheromones {
			most_pheromones = pheromones_on_block
			best_index = index
		}
	}

	if best_index == -1 || most_pheromones < PHEROMONE_SEEK_THRESHOLD {
		return {-1, -1}
	}

	return get_world_position_from_block_index(best_index)
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

Grid_Cell_Position :: [2]i32

// This is in block sizes
DEFAULT_SEARCH_RADIUS :: 40
DEFAULT_NUM_RAYS :: 10
RAY_INCREMENT :: GRID_CELL_SIZE / 10.0

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
				block, exists := get_block(state.grid, int(ray_block_index))
				if exists && !is_block_permeable(block.type) {
					// Block the ray if it hits a block that is impermeable
					break
				}
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

get_front_block :: proc(ant: Ant) -> (grid_position: Grid_Cell_Position) {
	origin_block_index := get_block_index(ant.pos)

	distance: f32 = 0
	ray_position := ant.pos + (ant.direction * RAY_INCREMENT)
	ray_block_index := get_block_index(ray_position)
	for ray_block_index == origin_block_index {
		ray_position += (ant.direction * RAY_INCREMENT)
		ray_block_index = get_block_index(ray_position)
	}
	grid_position = {i32(ray_position.x / GRID_CELL_SIZE), i32(ray_position.y / GRID_CELL_SIZE)}

	return
}

walk_ant :: proc(ant: ^Ant, grid: Grid) -> bool {
	// Ensure there is nothing in the way
	front_block_pos := get_front_block(ant^)
	block, block_real := get_block(grid, expand_values(front_block_pos))

	// Move forward if we're good 
	if block_real && is_block_permeable(block.type) {
		prev_pos := ant.pos
		ant.pos += ant.direction * rl.GetFrameTime() * ant.speed
		return true
	}
	// Otherwise we didn't move at all
	return false
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
