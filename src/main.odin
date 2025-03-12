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

Stage :: enum {
	Title,
	Game,
}

GameState :: struct {
	stage:  Stage,
	grid:   Grid,
	ants:   [dynamic]Ant,
	queen:  Queen,
	timer:  time.Stopwatch,
	paused: bool,
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
grid_target: rl.RenderTexture2D

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Ants!")
	defer rl.CloseWindow()

	grid := init_grid()
	defer deinit_grid(&grid)
	ants: [dynamic]Ant
	defer delete(ants)


	state := GameState {
		stage  = .Title,
		grid   = grid,
		ants   = ants,
		paused = false,
	}

	// Load assets
	emoji_font := rl.LoadFont("assets/NotoEmoji-Regular.ttf")
	ASSETS.fonts[.Emoji] = &emoji_font

	init_hud()
	defer deinit_hud()

	camera.zoom = 1.0

	grid_target = rl.LoadRenderTexture(WINDOW_WIDTH, WINDOW_HEIGHT)
	defer rl.UnloadRenderTexture(grid_target)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()

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

		update(&state)
		draw(&state)
	}
}

update :: proc(state: ^GameState) {
	switch (state.stage) {
	case .Title:
		if rl.IsKeyPressed(.SPACE) {
			start_game(state)
		}
	case .Game:
		if rl.IsKeyPressed(.SPACE) {
			state.paused = ~state.paused
		}
		update_grid(&state.grid)
		update_ants(state)
		update_hud()
	}
}

start_game :: proc(state: ^GameState) {
	time.stopwatch_start(&state.timer)
	state.stage = .Game

	// TODO: Set different levels, difficulties, etc. 

	// For now, spawn 3 ants 
	for _ in 0 ..< 3 {
		spawn_ant(state, immediately = true)
	}
}

draw :: proc(state: ^GameState) {
	switch (state.stage) {
	case .Title:
		draw_title()
	case .Game:
		draw_game(state)

		draw_hud(state^)
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

draw_game :: proc(state: ^GameState) {
	if draw_grid(state.grid) {
		state.grid.dirty = false
		state.grid.redraw_countdown = GRID_REFRESH_RATE
	}
	state.grid.redraw_countdown -= rl.GetFrameTime()

	rl.ClearBackground(rl.BLACK)
	rl.BeginMode2D(camera)
	defer rl.EndMode2D()
	// Render the grid separately as a texture 
	rl.DrawTextureRec(
		grid_target.texture,
		{0, 0, f32(grid_target.texture.width), -f32(grid_target.texture.height)},
		{0, 0},
		rl.WHITE,
	)

	// Draw the selected block 
	// TODO: Move this someplace appropriate
	selected_index := state.grid.selected_block
	rl.DrawRectangleRoundedLines(
		{
			f32(selected_index.x) * GRID_CELL_SIZE,
			f32(selected_index.y) * GRID_CELL_SIZE,
			GRID_CELL_SIZE,
			GRID_CELL_SIZE,
		},
		2,
		0,
		rl.RAYWHITE,
	)

	draw_queen()
	draw_ants(state.ants[:])
}
