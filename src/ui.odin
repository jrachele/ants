package ants

import "base:runtime"
import clay "clay-odin"
import renderer "clay-renderer"
import "core:fmt"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"

error_handler :: proc "c" (errorData: clay.ErrorData) {
	using errorData
	context = runtime.default_context()
	// Do something with the error data.
	fmt.println("[Clay] Error! %v: %s", errorType, errorText)
}

// Example measure text function
measure_text :: proc "c" (
	text: clay.StringSlice,
	config: ^clay.TextElementConfig,
	userData: rawptr,
) -> clay.Dimensions {
	// clay.TextElementConfig contains members such as fontId, fontSize, letterSpacing, etc..
	// Note: clay.String->chars is not guaranteed to be null terminated
	return {width = f32(text.length * i32(config.fontSize)), height = f32(config.fontSize)}
}

clay_memory: [^]u8
init_hud :: proc() {
	min_memory_size: u32 = clay.MinMemorySize()
	clay_memory := make([^]u8, min_memory_size)
	arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(uint(min_memory_size), clay_memory)
	clay.Initialize(
		arena,
		{width = WINDOW_WIDTH, height = WINDOW_HEIGHT},
		{handler = error_handler},
	)

	// Tell clay how to measure text
	clay.SetMeasureTextFunction(measure_text, nil)
}

deinit_hud :: proc() {
	free(clay_memory)
}

update_hud :: proc() {
	// Update internal pointer position for handling mouseover / click / touch events
	mouse_pos := rl.GetMousePosition()
	clay.SetPointerState(clay.Vector2{mouse_pos.x, mouse_pos.y}, rl.IsMouseButtonDown(.LEFT))
}

// Define some colors.
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}
COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
COLOR_BLACK :: clay.Color{0, 0, 0, 255}

// Layout config is just a struct that can be declared statically, or inline
sidebar_item_layout := clay.LayoutConfig {
	sizing = {width = clay.SizingGrow({}), height = clay.SizingFit({})},
	childAlignment = {x = .Center, y = .Center},
}

// Re-useable components are just normal procs.
sidebar_item_component :: proc(index: u32, text: string) {
	if clay.UI()(
	{
		id = clay.ID("SidebarBlob", index),
		layout = sidebar_item_layout,
		backgroundColor = {175, 195, 174, 100},
	},
	) {
		clay.Text(
			text,
			clay.TextConfig(
				{
					textColor = COLOR_BLACK,
					fontSize = 24,
					textAlignment = .Center,
					letterSpacing = 10,
					wrapMode = .Newlines,
				},
			),
		)
	}
}

// An example function to create your layout tree
draw_clay :: proc(state: GameState) {
	ant_counts := make(map[AntType]int)
	defer delete(ant_counts)

	for ant in state.ants {
		ant_counts[ant.type] += 1
	}

	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)
	counts_cstr := strings.to_cstring(&sb)

	// Begin constructing the layout.
	clay.BeginLayout()

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
			if (len(ant_counts) > 0) {

				i: u32 = 0
				for k, v in ant_counts {
					buf: [100]u8
					count_str := fmt.bprintf(buf[:], "%vs: %d", k, v)
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
			if state.paused {
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
		for ant in state.ants {
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
				for ant, i in selected_ants {
					buf: [1024]u8
					info := fmt.bprintf(
						buf[:],
						"%v\n%v\n->%v\nLD: %.2f (%v)\nPH:%.2fs\nID:%.2fs",
						ant.type,
						ant.state,
						ant.seekType,
						ant.load,
						ant.loadType,
						ant.pheromone_time_remaining,
						ant.idle_time_remaining,
					)
					sidebar_item_component(u32(i + len(ant_counts)), info)
				}
			}
		}
	}

	// Returns a list of render commands
	render_commands: clay.ClayArray(clay.RenderCommand) = clay.EndLayout()
	renderer.clayRaylibRender(&render_commands)
}

draw_hud :: proc(state: GameState) {
	draw_clay(state)

	// Miscellaneous stuff that doesn't need clay
	// Draw FPS 
	fpsBuf: [100]u8
	fps := fmt.bprintf(fpsBuf[:], "FPS: %v", rl.GetFPS())
	draw_text_align(rl.GetFontDefault(), fps, WINDOW_WIDTH, 0, .Right, 20, rl.WHITE)

}
