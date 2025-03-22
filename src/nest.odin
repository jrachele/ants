package ants

import "core:fmt"
import rl "vendor:raylib"
import sdl "vendor:sdl3"

Inventory :: [EnvironmentType]f32

NestPriority :: enum {
	None, // No priorities, randomly assign
	Food, // Seek honey
	Supply, // Seek wood and rock
	Defend, // Send armored and peons to danger areas to maintain order
	Attack, // Send elites to danger areas and attack
	Build, // Expand the nest, or deal with queued projects 
}

Nest :: struct {
	inventory:        Inventory,
	current_priority: NestPriority,
	priority_weight:  f32,
	health:           f32,
}

DEFAULT_NEST :: Nest {
	current_priority = .Food,
	priority_weight  = 75,
	health           = 20,
}

NEST_POS :: Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2}
NEST_SIZE :: 10

init_nest :: proc() -> (nest: Nest) {
	nest = DEFAULT_NEST
	return
}

draw_nest :: proc(nest: Nest) {
	color := rl.DARKPURPLE;color.a = 200

	color = rl.ColorLerp(color, rl.RED, (DEFAULT_NEST.health - nest.health) / DEFAULT_NEST.health)
	rl.DrawCircleV(NEST_POS, NEST_SIZE, color)

	// buf: [256]u8
	// hp_label := fmt.bprintf(buf[:], "%d HP", i32(nest.health))
	// label_color := rl.WHITE
	// label_color.a = 100
	// draw_text_align(
	// 	rl.GetFontDefault(),
	// 	hp_label,
	// 	i32(NEST_POS.x),
	// 	i32(NEST_POS.y - 20),
	// 	.Center,
	// 	10,
	// 	label_color,
	// )
	// TODO: Draw ant information over the nest for clarity
}

is_in_nest :: proc {
	is_in_nest_world_position,
	is_in_nest_block_position,
}

is_in_nest_world_position :: proc(pos: Vector2) -> bool {
	return vector2_distance(pos, NEST_POS) < NEST_SIZE
}

is_in_nest_block_position :: proc(block_position: [2]i32) -> bool {
	world_position := to_world_position(block_position)
	return is_in_nest_world_position(world_position + {GRID_CELL_SIZE / 2, GRID_CELL_SIZE / 2})
}

roll_ant_objective :: proc(nest: Nest) -> (ant_objective: AntObjective) {
	priority := nest.priority_weight
	priority = clamp(priority, 0, 1)

	switch (nest.current_priority) {
	case .None:
		ant_objective = random_select(
			[]AntObjective {
				AntObjective_Explore{},
				AntObjective_Forage {
					forage_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
				},
				AntObjective_War{},
				AntObjective_Build{},
			},
		)
	case .Defend, .Attack:
		ant_objective = random_select_priority(
			priority,
			AntObjective(AntObjective_War{}),
			[]AntObjective {
				AntObjective_Explore{},
				AntObjective_Forage {
					forage_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
				},
				AntObjective_Build{},
			},
		)
	case .Build:
		ant_objective = random_select_priority(
			priority,
			AntObjective(AntObjective_Build{}),
			[]AntObjective {
				AntObjective_Explore{},
				AntObjective_Forage {
					forage_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
				},
				AntObjective_War{},
			},
		)
	case .Food, .Supply:
		ant_objective = random_select_priority(
			priority,
			AntObjective(
				AntObjective_Forage {
					forage_type = nest.current_priority == .Supply ? random_select([]EnvironmentType{.Rock, .Wood}) : .Honey,
				},
			),
			[]AntObjective{AntObjective_Explore{}, AntObjective_Build{}, AntObjective_War{}},
		)
	}

	return
}
