package ants

import "core:fmt"
import "core:slice"
import rl "vendor:raylib"

// The grid will contain aspects of the environment 
GRID_CELL_SIZE :: 4
GRID_HEIGHT :: WINDOW_HEIGHT / GRID_CELL_SIZE
GRID_WIDTH :: WINDOW_WIDTH / GRID_CELL_SIZE

Grid_Cell_Position :: [2]i32
INVALID_BLOCK_POSITION := Grid_Cell_Position{-1, -1}

// Store a set of block indices 
Neighborhood :: map[i32]struct {}

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
	pheromones: [Pheromone]f32,
	amount:     f32,
}

Grid :: struct {
	data:                          [dynamic]EnvironmentBlock,
	dirty:                         bool,
	redraw_countdown:              f32,
	pheromone_diffusion_countdown: f32,
	selected_block:                [2]i32,
}

// Must add up to 100
BlockDistribution := [EnvironmentType]i32 {
	.Grass   = 60,
	.Dirt    = 28,
	.Honey   = 2,
	.Wood    = 5,
	.Rock    = 5,
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

get_block_ptr :: proc {
	get_block_xy_ptr,
	get_block_v2_ptr,
}

get_block_v2_ptr :: proc(grid: ^Grid, v: rl.Vector2) -> ^EnvironmentBlock {
	v := v / GRID_CELL_SIZE
	return get_block_xy_ptr(grid, i32(v.x), i32(v.y))
}

get_block_xy_ptr :: proc(grid: ^Grid, x: i32, y: i32) -> ^EnvironmentBlock {
	index := int((y * GRID_WIDTH) + x)

	// Probably should use actual error handling in this project
	if index < 0 || index >= len(grid.data) {
		return nil
	}

	// If a block is returned as a pointer, set the grid to dirty as it will likely be mutated 
	grid.dirty = true

	return &grid.data[index]
}

get_block :: proc {
	get_block_xy,
	get_block_v2,
	get_block_i,
}

get_block_v2 :: proc(grid: Grid, v: rl.Vector2) -> (EnvironmentBlock, bool) {
	v := v / GRID_CELL_SIZE
	return get_block_xy(grid, i32(v.x), i32(v.y))
}

get_block_xy :: proc(grid: Grid, x: i32, y: i32) -> (EnvironmentBlock, bool) {
	index := int(get_block_index(x, y))
	return get_block_i(grid, index)
}

get_block_i :: proc(grid: Grid, i: int) -> (EnvironmentBlock, bool) {
	if i < 0 || i >= len(grid.data) do return {}, false
	return grid.data[i], true
}

get_block_index :: proc {
	get_block_index_v2,
	get_block_index_xy,
}

get_block_index_xy :: proc(x: i32, y: i32) -> i32 {
	return (y * GRID_WIDTH) + x
}

get_block_index_v2 :: proc(v: rl.Vector2) -> i32 {
	return get_block_index_xy(i32(v.x / GRID_CELL_SIZE), i32(v.y / GRID_CELL_SIZE))
}

is_block_index_valid :: proc {
	is_block_index_valid_i,
	is_block_index_valid_xy,
}

is_block_index_valid_xy :: proc(x: i32, y: i32) -> bool {
	return is_block_index_valid_i(get_block_index(x, y))
}

is_block_index_valid_i :: proc(index: i32) -> bool {
	return index >= 0 && index < GRID_WIDTH * GRID_HEIGHT
}

grid_cell_to_world_pos :: proc(x: i32, y: i32) -> rl.Vector2 {
	return rl.Vector2{f32(x) * GRID_CELL_SIZE, f32(y) * GRID_CELL_SIZE}
}

get_selected_block :: proc(grid: Grid) -> (EnvironmentBlock, bool) {
	if grid.selected_block == INVALID_BLOCK_POSITION {
		return {}, false
	}

	return get_block(grid, grid.selected_block.x, grid.selected_block.y)
}

get_selected_block_ptr :: proc(grid: ^Grid) -> ^EnvironmentBlock {
	if grid.selected_block == INVALID_BLOCK_POSITION {
		return nil
	}

	return get_block_ptr(grid, grid.selected_block.x, grid.selected_block.y)
}

get_world_position_from_block_index :: proc(index: i32) -> rl.Vector2 {
	grid_position := Grid_Cell_Position{index % GRID_WIDTH, index / GRID_WIDTH}
	return rl.Vector2{f32(grid_position.x), f32(grid_position.y)} * GRID_CELL_SIZE
}

init_grid :: proc() -> (grid: Grid) {
	resize(&grid.data, GRID_WIDTH * GRID_HEIGHT)
	for y in 0 ..< i32(GRID_HEIGHT) {
		for x in 0 ..< i32(GRID_WIDTH) {
			index := get_block_index(x, y)
			block := &grid.data[index]
			// The nest should have no blocks, but lots of pheromones
			if is_in_nest(x, y) {
				block.pheromones[.General] = 100
				block.type = .Nothing
				block.amount = 0
			} else {
				block.type = select_random_block()
				// For types that can be picked up, add a random amount 
				if is_block_collectable(block.type) {
					block.amount = f32(rl.GetRandomValue(1, 100))
				}
			}

		}
	}

	grid.selected_block = INVALID_BLOCK_POSITION
	grid.dirty = true

	// TODO: Use wave function collapse to generate the map around the ants 
	return grid
}

deinit_grid :: proc(grid: ^Grid) {
	delete(grid.data)
}

MAX_PHEROMONES :: 100

PHEROMONE_DIFFUSION_RATE :: 1 // Second
// Each tick, decay the block to this percentage of its current amount, then begin the diffusion process
PHEROMONE_DECAY_COEFFICIENT :: 0.97
// Each tick of the diffusion, set the blocks around the current block to this amount of its pheromones
PHEROMONE_DIFFUSION_COEFFICIENT :: 0.01

update_grid :: proc(state: ^GameState) {
	mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)
	grid := &state.grid
	if (rl.IsMouseButtonPressed(.LEFT)) {
		grid_pos := mouse_pos / GRID_CELL_SIZE
		if i32(grid_pos.x) == grid.selected_block.x && i32(grid_pos.y) == grid.selected_block.y {
			// Deselect
			grid.selected_block = INVALID_BLOCK_POSITION
		} else {
			grid.selected_block = {i32(grid_pos.x), i32(grid_pos.y)}
			if grid.selected_block.x < 0 ||
			   grid.selected_block.x >= GRID_WIDTH ||
			   grid.selected_block.y < 0 ||
			   grid.selected_block.y >= GRID_HEIGHT {
				grid.selected_block = INVALID_BLOCK_POSITION
			}
		}
	}

	if state.paused do return

	diffused_pheromones := false
	for i in 0 ..< len(grid.data) {
		// Set the block to nothing if the amount is 0
		block := &grid.data[i]
		if block.amount <= 0 && is_block_collectable(block.type) {
			block.type = .Nothing
			grid.dirty = true
		}
	}

	if grid.pheromone_diffusion_countdown < 0 {
		// We will need to copy the grid completely (this is a bit expensive...)
		grid_copy := slice.clone(grid.data[:])
		defer delete(grid_copy)

		for y in 0 ..< i32(GRID_HEIGHT) {
			for x in 0 ..< i32(GRID_WIDTH) {
				// Ignore all decay and diffusion on pheromones within the nest
				if is_in_nest(x, y) do continue

				index := get_block_index(x, y)
				reference_block := grid_copy[index]
				block_mut := &grid.data[index]

				// Decay
				for ph in Pheromone {
					block_mut.pheromones[ph] =
						clamp(reference_block.pheromones[ph], 0, MAX_PHEROMONES) *
						PHEROMONE_DECAY_COEFFICIENT
					if block_mut.pheromones[ph] < 0.5 {
						block_mut.pheromones[ph] = 0
					}
				}

				// Diffusion
				for oy in i32(-1) ..= 1 {
					for ox in i32(-1) ..= 1 {
						// Ignore the center piece
						if oy == 0 && ox == 0 do continue
						neighbor_index := get_block_index(x + ox, y + oy)
						if !is_block_index_valid(neighbor_index) do continue
						for ph in Pheromone {
							amount :=
								reference_block.pheromones[ph] * PHEROMONE_DIFFUSION_COEFFICIENT
							grid.data[neighbor_index].pheromones[ph] = clamp(
								grid.data[neighbor_index].pheromones[ph] + amount,
								0,
								MAX_PHEROMONES,
							)
						}
					}
				}
			}
		}

		diffused_pheromones = true
	}

	// Reset the pheromone diffusion timer 
	if diffused_pheromones {
		grid.pheromone_diffusion_countdown = PHEROMONE_DIFFUSION_RATE
		grid.dirty = true
	}

	grid.redraw_countdown -= rl.GetFrameTime()
	grid.pheromone_diffusion_countdown -= rl.GetFrameTime()

}

GRID_REFRESH_RATE :: 1 // Second
draw_grid :: proc(grid: Grid) -> bool {
	// Draw the grid on a timer
	if !grid.dirty || grid.redraw_countdown > 0 do return false

	rl.BeginTextureMode(grid_target)
	defer rl.EndTextureMode()

	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, get_block_color(.Dirt))

	// TODO: Figure out the bounds and only draw whats within the camera view 
	for y in 0 ..< i32(GRID_HEIGHT) {
		for x in 0 ..< i32(GRID_WIDTH) {
			block, ok := get_block(grid, x, y)
			if !ok do continue

			color := get_block_color(block.type)
			for p in Pheromone {
				pheromone_color := get_pheromone_color(p)
				color = rl.ColorLerp(
					color,
					pheromone_color,
					block.pheromones[p] / (MAX_PHEROMONES * 4),
				)
			}

			// Impermeable types that can be picked up should interp based on amount 
			if is_block_collectable(block.type) {
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

	return true
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
