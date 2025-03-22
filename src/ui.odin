package ants

import "base:runtime"
import clay "clay-odin"
import renderer "clay-renderer"
import "core:fmt"
import "core:mem"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"

error_handler :: proc "c" (errorData: clay.ErrorData) {
	using errorData
	context = runtime.default_context()
	// Do something with the error data.
	fmt.println("[Clay] Error! %v: %s", errorType, errorText)
}

init_hud :: proc(clay_memory: ^[^]u8, window_width: f32, window_height: f32) {
	min_memory_size: u32 = clay.MinMemorySize()
	clay_memory^ = make([^]u8, min_memory_size)
	arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(uint(min_memory_size), clay_memory^)
	clay.Initialize(
		arena,
		{width = window_width, height = window_height},
		{handler = error_handler},
	)

	// Tell clay how to measure text
	clay.SetMeasureTextFunction(renderer.measureText, nil)

	// Load fonts for the clay renderer
	for font in Fonts {
		renderer.raylibFonts[font] = {
			fontId = u16(font),
			font   = assets.fonts[font],
		}
	}
}

update_hud :: proc() {
	// Update internal pointer position for handling mouseover / click / touch events
	mouse_pos := rl.GetMousePosition()
	clay.SetPointerState(clay.Vector2{mouse_pos.x, mouse_pos.y}, rl.IsMouseButtonDown(.LEFT))
}

// Layout config is just a struct that can be declared statically, or inline
sidebar_item_layout := clay.LayoutConfig {
	sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
	childAlignment = {x = .Center, y = .Center},
}

// Re-useable components are just normal procs.
sidebar_item_component :: proc(index: u32, text: string) {
	if clay.UI()(
	{
		id = clay.ID(text, index),
		layout = sidebar_item_layout,
		backgroundColor = {175, 195, 174, 100},
	},
	) {
		clay.Text(
			text,
			clay.TextConfig(
				{
					// textColor = Colors[.Black],
					fontSize      = 24,
					textAlignment = .Center,
					letterSpacing = 10,
					wrapMode      = .None,
				},
			),
		)
	}
}

// An example function to create your layout tree
draw_clay :: proc(data: GameData) {
	ant_counts: [AntType]int

	for ant in data.ants {
		ant_counts[ant.type] += 1
	}

	inventory := data.nest.inventory

	CLAY_ARENA_SIZE :: 4196
	render_buf := make([]u8, CLAY_ARENA_SIZE)
	defer delete(render_buf)

	arena: mem.Arena
	mem.arena_init(&arena, render_buf)
	{
		context.allocator = mem.arena_allocator(&arena)
		clay.BeginLayout() // Begin constructing the layout.

		// An example of laying out a UI with a fixed-width sidebar and flexible-width main content
		// NOTE: To create a scope for child components, the Odin API uses `if` with components that have children
		if clay.UI()(
		{
			id = clay.ID("OuterContainer"),
			layout = {
				sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
				padding = {16, 16, 16, 16},
				childGap = 16,
			},
			backgroundColor = {0, 0, 0, 0},
		},
		) {
			if clay.UI()(
			{
				id = clay.ID("SideBar"),
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {width = clay.SizingFixed(300), height = clay.SizingFit({})},
					padding = {16, 16, 16, 16},
					childGap = 16,
				},
				backgroundColor = {0, 0, 0, 0},
			},
			) {
				test_bool: bool
				Button("Test!", &test_bool, "\uf164")

				if (test_bool) {
					fmt.printfln("Button pressed!")
				}

				test_f32: f32 = 20

				Slider(&test_f32, 0, 40, "Test f32")

				i: u32 = 0
				for ant_type in AntType {
					if ant_counts[ant_type] > 0 {
						count_str := fmt.aprintfln("%vs: %d", ant_type, ant_counts[ant_type])
						sidebar_item_component(i, count_str)
						i += 1
					}
				}

				// TODO: add separator
				i = 0
				for block_type in EnvironmentType {
					if inventory[block_type] > 0 {
						count_str := fmt.aprintfln("%v: %.2f", block_type, inventory[block_type])
						sidebar_item_component(i, count_str)
						i += 1
					}
				}
			}

			if clay.UI()(
			{
				id = clay.ID("MainContent"),
				layout = {
					sizing = {width = clay.SizingGrow({}), height = clay.SizingGrow({})},
					childAlignment = {x = .Center},
				},
				backgroundColor = {0, 0, 0, 0},
			},
			) {
				if data.paused {
					clay.Text(
						"PAUSED",
						clay.TextConfig(
							{
								textColor = {255, 255, 255, 130},
								fontSize = 36,
								textAlignment = .Center,
								letterSpacing = 10,
							},
						),
					)
				}
			}

			selected_ants: [dynamic]Ant
			defer delete(selected_ants)
			for ant in data.ants {
				if ant.selected {
					append(&selected_ants, ant)
				}
			}

			if clay.UI()(
			{
				id = clay.ID("SideBar2"),
				layout = {
					layoutDirection = .TopToBottom,
					sizing = {width = clay.SizingFixed(500), height = clay.SizingFit({})},
					padding = {16, 16, 16, 16},
					childGap = 16,
				},
				backgroundColor = {0, 0, 0, 0},
			},
			) {
				if len(selected_ants) > 0 {
					ant := selected_ants[0]
					action := ""

					info := fmt.aprintfln(
						"%v\n%v\n%v\nLD: %.2f (%v)\nPH:%.2fs\n",
						ant.type,
						action,
						ant.objective,
						ant.load,
						ant.load_type,
						ant.pheromone_time_remaining,
					)
					sidebar_item_component(u32(len(ant_counts)), info)
				}

				if data.grid.selected_block_position != INVALID_BLOCK_POSITION {
					block, ok := get_selected_block(data.grid)
					if !ok {
						return
					}

					sb := strings.builder_make()
					fmt.sbprintfln(&sb, "Pheromones:")
					for pheromone in Pheromone {
						amt := block.pheromones[pheromone]
						fmt.sbprintfln(&sb, "%v: %.2f", pheromone, amt)
					}
					pheromone_info := strings.to_string(sb)

					info := fmt.aprintfln("%v\n%.2f\n%s", block.type, block.amount, pheromone_info)
					sidebar_item_component(0, info)
				}
			}
		}

		// Returns a list of render commands
		render_commands: clay.ClayArray(clay.RenderCommand) = clay.EndLayout()
		renderer.clayRaylibRender(&render_commands)
	}
}

draw_hud :: proc(data: GameData) {
	draw_clay(data)

	// Miscellaneous stuff that doesn't need clay
	// Draw FPS 
	// fpsBuf: [100]u8
	// fps := fmt.bprintf(fpsBuf[:], "FPS: %v", rl.GetFPS())
	// draw_text_align(rl.GetFontDefault(), fps, WINDOW_WIDTH, 0, .Right, 20, rl.WHITE)

}
