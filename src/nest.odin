package ants

import rl "vendor:raylib"

Inventory :: [EnvironmentType]f32

Nest :: struct {
	inventory:        Inventory,
	current_priority: AntPriority,
	priority_weight:  u8,
	health:           f32,
}

DEFAULT_NEST :: Nest {
	current_priority = .Food,
	priority_weight  = 75,
	health           = 1000,
}

NEST_POS :: rl.Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2}
NEST_SIZE :: 10

init_nest :: proc() -> (nest: Nest) {
	nest = DEFAULT_NEST
	return
}

draw_nest :: proc() {
	color := rl.DARKPURPLE;color.a = 200
	rl.DrawCircleV(NEST_POS, NEST_SIZE, color)
	// TODO: Draw ant information over the nest for clarity
}

is_in_nest :: proc {
	is_in_nest_v2,
	is_in_nest_xy,
}

is_in_nest_v2 :: proc(pos: rl.Vector2) -> bool {
	return rl.Vector2Distance(pos, NEST_POS) < NEST_SIZE
}

is_in_nest_xy :: proc(x: i32, y: i32) -> bool {
	block_position := rl.Vector2{f32(x) * GRID_CELL_SIZE, f32(y) * GRID_CELL_SIZE}
	return is_in_nest_v2(block_position + {GRID_CELL_SIZE / 2, GRID_CELL_SIZE / 2})
}

roll_ant_objective :: proc(nest: Nest) -> (ant_objective: AntObjective) {
	priority := i32(nest.priority_weight)
	priority = clamp(priority, 0, 100)

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
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_objective = AntObjective_War{}
		} else {
			ant_objective = random_select(
				[]AntObjective {
					AntObjective_Explore{},
					AntObjective_Forage {
						forage_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
					},
					AntObjective_Build{},
				},
			)
		}
	case .Build:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_objective = AntObjective_Build{}
		} else {
			ant_objective = random_select(
				[]AntObjective {
					AntObjective_Explore{},
					AntObjective_Forage {
						forage_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
					},
					AntObjective_War{},
				},
			)
		}
	case .Food, .Supply:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_objective = AntObjective_Forage {
				forage_type = nest.current_priority == .Supply ? random_select([]EnvironmentType{.Rock, .Wood}) : .Honey,
			}
		} else {
			ant_objective = random_select(
				[]AntObjective{AntObjective_Explore{}, AntObjective_Build{}, AntObjective_War{}},
			)
		}

	}

	return
}
