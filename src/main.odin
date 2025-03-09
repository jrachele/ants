package ants

import "base:builtin"
import clay "clay-odin"
import renderer "clay-renderer"
import "core:math"
import "core:reflect"
import "core:slice"
import "core:time"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

CAMERA_MOVE_SPEED :: 400

// The grid will contain aspects of the environment 
GRID_CELL_SIZE :: 5
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

Stage :: enum {
	Title,
	Game,
}

GameState :: struct {
	stage: Stage,
	grid:  [dynamic]EnvironmentBlock,
	ants:  [dynamic]Ant,
	queen: Ant,
	timer: time.Stopwatch,
}

Fonts :: enum {
	Emoji,
	Serif,
	SansSerif,
}

Assets :: struct {
	fonts: [Fonts]^rl.Font,
}

ASSETS: Assets

// Globals
camera: rl.Camera2D

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Ants!")
	defer rl.CloseWindow()

	grid := init_grid()
	defer delete(grid)
	ants: [dynamic]Ant
	defer delete(ants)

	queen := Ant {
		health = 100,
		angle  = math.PI / 2,
		type   = .Queen,
		pos    = {WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2},
	}

	state := GameState {
		stage = .Title,
		grid  = grid,
		ants  = ants,
		queen = queen,
	}

	// Load assets
	emoji_font := rl.LoadFont("assets/NotoEmoji-Regular.ttf")
	ASSETS.fonts[.Emoji] = &emoji_font

	camera.zoom = 1.0

	for !rl.WindowShouldClose() {
		update(&state)

		// Translate based on mouse right click
		if (rl.IsMouseButtonDown(rl.MouseButton.LEFT)) {
			delta := rl.GetMouseDelta()
			delta *= -1.0 / camera.zoom
			camera.target += delta
		} else {
			if (rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)) {
				camera.target.x -= rl.GetFrameTime() * CAMERA_MOVE_SPEED
			}
			if (rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)) {
				camera.target.y += rl.GetFrameTime() * CAMERA_MOVE_SPEED
			}
			if (rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT)) {
				camera.target.x += rl.GetFrameTime() * CAMERA_MOVE_SPEED
			}
			if (rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)) {
				camera.target.y -= rl.GetFrameTime() * CAMERA_MOVE_SPEED
			}
		}
		// Zoom based on mouse wheel
		wheel := rl.GetMouseWheelMove()
		if (wheel != 0) {
			// Get the world point that is under the mouse
			mouseWorldPos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

			// Set the offset to where the mouse is
			camera.offset = rl.GetMousePosition()

			// Set the target to match, so that the camera maps the world space point 
			// under the cursor to the screen space point under the cursor at any zoom
			camera.target = mouseWorldPos

			// Zoom increment
			scaleFactor := 1.0 + (0.25 * math.abs(wheel))
			if (wheel < 0) do scaleFactor = 1.0 / scaleFactor
			camera.zoom = clamp(camera.zoom * scaleFactor, 0.125, 64.0)
		}

		draw(state)
	}
}

update :: proc(state: ^GameState) {
	switch (state.stage) {
	case .Title:
		if rl.IsKeyPressed(.SPACE) {
			start_game(state)
		}
	case .Game:
		if time.stopwatch_duration(state.timer) > ANT_SPAWN_RATE * time.Second {
			// Just spawn peons for now
			spawn_ant(state.queen, &state.ants)
			time.stopwatch_reset(&state.timer)
			time.stopwatch_start(&state.timer)
		}

		update_ants(&state.ants)
	}
}

start_game :: proc(state: ^GameState) {
	time.stopwatch_start(&state.timer)
	state.stage = .Game
}

draw :: proc(state: GameState) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	switch (state.stage) {
	case .Title:
		draw_title()
	case .Game:
		rl.BeginMode2D(camera)
		draw_game(state)
		rl.EndMode2D()

		draw_hud(state)
	}
}
draw_title :: proc() {
	rl.ClearBackground(rl.RAYWHITE)
	draw_text_align(
		rl.GetFontDefault(),
		"ANTS!",
		WINDOW_WIDTH / 2,
		(WINDOW_HEIGHT / 2) - 40,
		.Center,
		80,
		rl.BLACK,
	)
}

draw_game :: proc(state: GameState) {
	rl.ClearBackground(rl.BLACK)
	draw_grid(state.grid[:])
	draw_queen(state.queen)
	draw_ants(state.ants[:])
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

draw_grid :: proc(grid: []EnvironmentBlock) {
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
				base_color = rl.PINK
			case .Wood:
				base_color = rl.BROWN
			case .Rock:
				base_color = rl.DARKGRAY
			case .AntNest:
				base_color = rl.GRAY
			}

			pheremone_color := rl.BEIGE

			color := rl.ColorLerp(
				base_color,
				pheremone_color,
				f32(block.pheremone_amount) / f32(size_of(u8)),
			)

			rl.DrawRectangle(
				i32(x * GRID_CELL_SIZE),
				i32(y * GRID_CELL_SIZE),
				GRID_CELL_SIZE,
				GRID_CELL_SIZE,
				color,
			)
		}
	}
}
