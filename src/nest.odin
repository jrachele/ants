package ants

import rl "vendor:raylib"

Inventory :: [EnvironmentType]f32

Nest :: struct {
	inventory:        Inventory,
	current_priority: AntPriority,
	priority_weight:  u8,
}

NEST_POS :: rl.Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2}
NEST_SIZE :: 10

init_nest :: proc() -> (nest: Nest) {
	// Set the current priority to 75% food by default
	nest.current_priority = .Food
	nest.priority_weight = 75

	return
}

draw_nest :: proc() {
	color := rl.DARKPURPLE;color.a = 200
	rl.DrawCircleV(NEST_POS, NEST_SIZE, color)
	// TODO: Draw ant information over the nest for clarity
}

is_in_nest :: proc(ant: Ant) -> bool {
	return rl.Vector2Distance(ant.pos, NEST_POS) < NEST_SIZE
}

ant_state_from_nest :: proc(nest: Nest) -> (ant_state: AntState) {
	priority := i32(nest.priority_weight)
	priority = clamp(priority, 0, 100)

	switch (nest.current_priority) {
	case .None:
		ant_state = random_select(
			[]AntState {
				AntState_Wander{},
				AntState_Seek{seek_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood})},
				AntState_Danger{fleeing = false},
				AntState_Build{},
			},
		)
	case .Defend, .Attack:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_state = AntState_Danger {
				fleeing = nest.current_priority == .Defend,
			}
		} else {
			ant_state = random_select(
				[]AntState {
					AntState_Wander{},
					AntState_Seek {
						seek_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
					},
					AntState_Build{},
				},
			)
		}
	case .Build:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_state = AntState_Build{}
		} else {
			ant_state = random_select(
				[]AntState {
					AntState_Wander{},
					AntState_Seek {
						seek_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
					},
					AntState_Danger{fleeing = false},
				},
			)
		}
	case .Food, .Supply:
		roll := rl.GetRandomValue(0, priority)
		// We will get the desired state 
		if roll < priority {
			ant_state = AntState_Seek {
				seek_type = nest.current_priority == .Supply ? random_select([]EnvironmentType{.Rock, .Wood}) : .Honey,
			}
		} else {
			ant_state = random_select(
				[]AntState {
					AntState_Wander{},
					AntState_Seek {
						seek_type = random_select([]EnvironmentType{.Honey, .Rock, .Wood}),
					},
					AntState_Danger{fleeing = false},
				},
			)
		}

	}

	return
}
