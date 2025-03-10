package ants

import rl "vendor:raylib"
import "vendor:raylib/rlgl"

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
	AntNest,
}

EnvironmentBlock :: struct {
	type:             EnvironmentType,
	amount:           f32,
	pheremone_amount: u8,
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
	.AntNest = 0,
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

get_block :: proc(grid: []EnvironmentBlock, x: i32, y: i32) -> ^EnvironmentBlock {
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
			block.type = .AntNest
		}
	}

	// TODO: Use wave function collapse to generate the map around the ants 
	return grid
}

import "core:fmt"
draw_grid :: proc(grid: []EnvironmentBlock) {
	rlgl.SetTexture(rl.GetShapesTexture().id)
	defer rlgl.SetTexture(0)

	rlgl.SetBlendMode(i32(rlgl.BlendMode.ALPHA))
	rlgl.Begin(rlgl.TRIANGLES)
	defer rlgl.End()

	for y in 0 ..< i32(GRID_HEIGHT) {
		for x in 0 ..< i32(GRID_WIDTH) {
			block := get_block(grid, x, y)
			base_color: rl.Color
			switch (block.type) {
			case .Dirt:
				base_color = rl.DARKBROWN
			case .Honey:
				base_color = rl.YELLOW
			case .Grass:
				base_color = rl.DARKGREEN
			case .Nothing:
				base_color = rl.BEIGE
			case .Wood:
				base_color = rl.BROWN
			case .Rock:
				base_color = rl.DARKGRAY
			case .AntNest:
				base_color = rl.GRAY
			}

			pheremone_color := rl.PINK

			color := rl.ColorLerp(base_color, pheremone_color, f32(block.pheremone_amount) / 255)

			x1 := f32(x * GRID_CELL_SIZE)
			x2 := x1 + GRID_CELL_SIZE
			y1 := f32(y * GRID_CELL_SIZE)
			y2 := y1 + GRID_CELL_SIZE

			topLeft := rl.Vector2{x1, y1}
			bottomLeft := rl.Vector2{x1, y2}
			topRight := rl.Vector2{x2, y1}
			bottomRight := rl.Vector2{x2, y2}

			rlgl.Color4ub(color.r, color.g, color.b, color.a)

			rlgl.Vertex2f(topLeft.x, topLeft.y)
			rlgl.Vertex2f(bottomLeft.x, bottomLeft.y)
			rlgl.Vertex2f(topRight.x, topRight.y)

			rlgl.Vertex2f(topRight.x, topRight.y)
			rlgl.Vertex2f(bottomLeft.x, bottomLeft.y)
			rlgl.Vertex2f(bottomRight.x, bottomRight.y)
		}
	}
}
