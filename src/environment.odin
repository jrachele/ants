package ants

import "core:math"
import rl "vendor:raylib"

ANT_PHEROMONE_RATE :: 1.0
try_spread_pheromone :: proc(ant: ^Ant, grid: ^Grid, pheromone: Pheromone) -> bool {
	if ant.pheromone_time_remaining <= 0 {
		block := get_block_ptr_from_world_position(grid, ant.pos)
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

find_item :: proc(
	ant: ^Ant,
	neighborhood: Neighborhood,
	grid: Grid,
	block_type: EnvironmentType,
) -> Vector2 {
	best_index: int = -1
	best_distance: f32
	for index in neighborhood {
		block, _ := get_block_from_index(grid, index)
		if block.type == block_type {
			block_position := to_world_position(index)
			block_distance := vector2_distance(ant.pos, block_position)
			if best_index == -1 || block_distance < best_distance {
				best_index = index
				best_distance = block_distance
			}
		}
	}

	if best_index == -1 {
		return {-1, -1}
	}

	return to_world_position(best_index)
}

// Any blocks with a pheromone count below this will not be considered by the ant 
PHEROMONE_SEEK_THRESHOLD :: 10
find_most_pheromones :: proc(
	ant: ^Ant,
	neighborhood: Neighborhood,
	grid: Grid,
	pheromone: Pheromone,
) -> Vector2 {
	most_pheromones: f32 = 0
	best_index: int = -1
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

	return to_world_position(best_index)
}

// This is in block sizes
DEFAULT_SEARCH_RADIUS :: 40
DEFAULT_NUM_RAYS :: 10
RAY_INCREMENT :: GRID_CELL_SIZE / 10.0

get_neighborhood :: proc(
	ant: Ant,
	data: GameData,
	radius: f32 = DEFAULT_SEARCH_RADIUS,
	cone_degrees: f32 = 150, // 360 here would be full vision
) -> (
	neighborhood: Neighborhood,
) {

	origin_block_index := to_index(ant.pos)

	for i in 0 ..< DEFAULT_NUM_RAYS {
		angle := f32(i) * (cone_degrees / DEFAULT_NUM_RAYS) - (cone_degrees / 2)
		direction := vector2_normalize(vector2_rotate(ant.direction, math.to_radians(angle)))

		ray_position := ant.pos + (direction * RAY_INCREMENT)
		distance: f32 = 0
		for distance < DEFAULT_SEARCH_RADIUS {
			ray_block_index := to_index(ray_position)
			// TODO: Use a real raycasting algorithm that does not rely on pure naive chance... after the jam...
			// Add all blocks touched by the ray in the set
			if origin_block_index != ray_block_index {
				neighborhood[ray_block_index] = {}
				block, exists := get_block(data.grid, ray_block_index)
				if exists && !is_block_permeable(block.type) {
					// Block the ray if it hits a block that is impermeable
					break
				}
			}
			distance = vector2_distance(ant.pos, ray_position)
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

get_front_block :: proc(entity: Entity) -> (grid_position: Grid_Cell_Position) {
	origin_block_index := to_index(entity.pos)

	distance: f32 = 0
	ray_position := entity.pos + (entity.direction * RAY_INCREMENT)
	ray_block_index := to_index(ray_position)
	for ray_block_index == origin_block_index {
		ray_position += (entity.direction * RAY_INCREMENT)
		ray_block_index = to_index(ray_position)
	}
	grid_position = {i32(ray_position.x / GRID_CELL_SIZE), i32(ray_position.y / GRID_CELL_SIZE)}

	return
}

is_block_collectable :: proc(type: EnvironmentType) -> bool {
	switch type {
	case .Dirt, .Grass, .Nothing:
		return false
	case .Honey, .Rock, .Wood:
		return true
	}
	return true
}

is_block_permeable :: proc(type: EnvironmentType) -> bool {
	switch (type) {
	case .Grass, .Dirt, .Nothing:
		return true
	case .Rock, .Wood:
		return false
	case .Honey:
		return false
	}

	return false
}
