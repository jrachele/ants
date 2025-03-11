package ants

import rl "vendor:raylib"

// The grid will contain aspects of the environment 
GRID_CELL_SIZE :: 4
GRID_HEIGHT :: WINDOW_HEIGHT / GRID_CELL_SIZE
GRID_WIDTH :: WINDOW_WIDTH / GRID_CELL_SIZE

EnvironmentType :: enum {
	Nothing,
	Grass,
	Rock,
	Wood,
	Honey,
	Dirt,
}

Pheromone :: enum {
	General,
	Forage,
	Danger,
	Build,
}

EnvironmentBlock :: struct {
	type:       EnvironmentType,
	pheromones: [Pheromone]u8,
	amount:     f32,
	in_nest:    bool,
}

// TODO: Look into wave function collapse or similar for generating areas that make more sense 
// Must add up to 100
BlockDistribution := [EnvironmentType]i32 {
	.Grass   = 40,
	.Dirt    = 20,
	.Honey   = 2,
	.Wood    = 18,
	.Rock    = 20,
	.Nothing = 0,
}

select_random_block :: proc() -> EnvironmentType {
	choice := rl.GetRandomValue(0, 100)
	sum: i32 = 0
	for e in EnvironmentType {
		if e == .Nothing do continue
		sum += BlockDistribution[e]
		if choice <= sum {
			return e
		}
	}

	return EnvironmentType.Nothing
}

get_block :: proc {
	get_block_xy,
	get_block_v2,
}

get_block_v2 :: proc(grid: []EnvironmentBlock, v: rl.Vector2) -> ^EnvironmentBlock {
	v := v / GRID_CELL_SIZE
	return get_block_xy(grid, i32(v.x), i32(v.y))
}

get_block_xy :: proc(grid: []EnvironmentBlock, x: i32, y: i32) -> ^EnvironmentBlock {
	index := int((y * GRID_WIDTH) + x)

	// Probably should use actual error handling in this project
	if index < 0 || index >= len(grid) {
		return nil
	}

	return &grid[index]
}

init_grid :: proc() -> (grid: [dynamic]EnvironmentBlock) {
	resize(&grid, GRID_WIDTH * GRID_HEIGHT)
	for i in 0 ..< len(grid) {
		grid[i].type = select_random_block()

		// For types that can be picked up, add a random amount 
		#partial switch (grid[i].type) {
		case .Rock, .Wood, .Honey:
			grid[i].amount = f32(rl.GetRandomValue(1, 100))
		}
	}

	// Create a patch of ant space at the middle of the screen 
	// Make it occupy the middle 20%
	center_point := [2]i32{GRID_WIDTH / 2, GRID_HEIGHT / 2}
	center_size := [2]i32{GRID_WIDTH / 12, GRID_HEIGHT / 12}
	for i in 0 ..< center_size.x {
		for j in 0 ..< center_size.y {
			x := center_point.x - (center_size.x / 2) + i
			y := center_point.y - (center_size.y / 2) + j
			block := get_block(grid[:], x, y)
			block.type = .Dirt
			block.in_nest = true
		}
	}

	// TODO: Use wave function collapse to generate the map around the ants 
	return grid
}

import "core:fmt"
draw_grid :: proc(grid: []EnvironmentBlock) {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, get_block_color(.Dirt))

	for y in 0 ..< i32(GRID_HEIGHT) {
		for x in 0 ..< i32(GRID_WIDTH) {
			block := get_block(grid, x, y)

			color := get_block_color(block.type)
			for p in Pheromone {
				pheromone_color := get_pheromone_color(p)
				color = rl.ColorLerp(color, pheromone_color, f32(block.pheromones[p]) / 255)
			}

			// Impermeable types that can be picked up should interp based on amount 
			if (!is_block_permeable(block.type)) {
				color = rl.ColorLerp(get_block_color(.Dirt), color, block.amount / 100)
			}

			switch (block.type) {
			case .Grass, .Dirt, .Nothing:
				rl.DrawRectangle(
					x * GRID_CELL_SIZE,
					y * GRID_CELL_SIZE,
					GRID_CELL_SIZE,
					GRID_CELL_SIZE,
					color,
				)
			case .Rock, .Wood, .Honey:
				radius: i32 = GRID_CELL_SIZE / 2
				rl.DrawCircle(
					(x * GRID_CELL_SIZE) + radius,
					(y * GRID_CELL_SIZE) + radius,
					GRID_CELL_SIZE / 2,
					color,
				)
			}
		}
	}
}

// TODO consider using [EnvironmentType]rl.Color for this, or making a block metadata struct similar to the ants' one
get_block_color :: proc(type: EnvironmentType) -> rl.Color {
	switch (type) {
	case .Nothing:
		fallthrough
	case .Dirt:
		return rl.BROWN
	case .Honey:
		return rl.YELLOW
	case .Grass:
		return rl.DARKGREEN
	case .Wood:
		return rl.DARKBROWN
	case .Rock:
		return rl.DARKGRAY
	}

	return rl.PINK
}

is_block_permeable :: proc(type: EnvironmentType) -> bool {
	switch (type) {
	case .Grass, .Dirt, .Nothing:
		return true
	case .Rock, .Wood:
		return false
	case .Honey:
		// FIXME: Set this to false after fixing neighborhood bug 
		return true
	}

	return false
}

get_pheromone_color :: proc(type: Pheromone) -> rl.Color {
	switch (type) {
	case .General:
		return rl.PURPLE
	case .Forage:
		return rl.DARKGREEN
	case .Danger:
		return rl.RED
	case .Build:
		return rl.SKYBLUE
	}

	return rl.PINK
}
