package ants

import "core:fmt"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"

// TODO: Use clay for this 
draw_hud :: proc(state: GameState) {
	ant_counts := make(map[AntType]int)
	defer delete(ant_counts)

	for ant in state.ants {
		ant_counts[ant.type] += 1
	}

	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)
	for k, v in ant_counts {
		fmt.sbprintfln(&sb, "%vs: %d", k, v)
	}
	counts_cstr := strings.to_cstring(&sb)
	rl.DrawText(counts_cstr, 8, 8, 20, rl.RAYWHITE)

	// Draw FPS 
	fpsBuf: [100]u8
	fps := fmt.bprintf(fpsBuf[:], "FPS: %v", rl.GetFPS())
	draw_text_align(rl.GetFontDefault(), fps, WINDOW_WIDTH, 0, .Right, 20, rl.WHITE)
}
