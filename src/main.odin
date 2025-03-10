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
		rl.BeginDrawing()
		defer rl.EndDrawing()

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
		update_ants(state)
	}
}

start_game :: proc(state: ^GameState) {
	time.stopwatch_start(&state.timer)
	state.stage = .Game
}

draw :: proc(state: GameState) {
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
