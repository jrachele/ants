package ants

import "core:fmt"
import "core:testing"
import "core:time"
import "system"
import rl "vendor:raylib"

Ant_Action_Blackboard :: struct {
	creature:         ^Creature,
	grid:             Grid,
	target_location:  rl.Vector2,
	using wait_timer: Ant_Wait_Timer,
}

Ant_Wait_Timer :: struct {
	wait_duration: time.Duration,
	stopwatch:     time.Stopwatch,
}

// The wait action is a "Complex" action but it actually has no children and just relies on evaluating conditions
// Sometimes actions like this are useful.
Wait_Action :: proc(blackboard: ^Ant_Action_Blackboard) -> system.Action(Ant_Action_Blackboard) {
	return system.Action_Complex(Ant_Action_Blackboard) {
		name = "Wait",
		blackboard = blackboard,
		pre_condition = proc(bb: Ant_Action_Blackboard) -> bool {
			return time.stopwatch_duration(bb.stopwatch) < bb.wait_duration
		},
		post_condition = proc(bb: Ant_Action_Blackboard) -> bool {
			return time.stopwatch_duration(bb.stopwatch) >= bb.wait_duration
		},
	}
}


Walk_Action_Children := []proc(
	blackboard: ^Ant_Action_Blackboard,
) -> system.Action(Ant_Action_Blackboard) {
	Turn_Towards_Target_Action,
	Avoid_Collision_Action,
	Take_Step_Action,
}

Walk_Action :: proc(blackboard: ^Ant_Action_Blackboard) -> system.Action(Ant_Action_Blackboard) {
	return system.Action_Complex(Ant_Action_Blackboard) {
		name = "Walk",
		blackboard = blackboard,
		pre_condition = proc(bb: Ant_Action_Blackboard) -> bool {
			return rl.Vector2Distance(bb.creature.pos, bb.target_location) > 1
		},
		post_condition = proc(bb: Ant_Action_Blackboard) -> bool {
			return rl.Vector2Distance(bb.creature.pos, bb.target_location) < 1
		},
		// Lock in
		children = Walk_Action_Children,
	}
}

Avoid_Collision_Children := []proc(
	blackboard: ^Ant_Action_Blackboard,
) -> system.Action(Ant_Action_Blackboard){Steer_Away_Action, Walk_Action}

Avoid_Collision_Action :: proc(
	blackboard: ^Ant_Action_Blackboard,
) -> system.Action(Ant_Action_Blackboard) {
	// Create a local blackboard when avoiding collisions instead of taking a global one 
	return system.Action_Complex(Ant_Action_Blackboard) {
		name = "Avoid collision",
		blackboard = blackboard,
		pre_condition = proc(bb: Ant_Action_Blackboard) -> bool {
			return is_blocked(bb.creature^, bb.grid)
		},
		post_condition = proc(bb: Ant_Action_Blackboard) -> bool {
			return !is_blocked(bb.creature^, bb.grid)
		},
		// Avoid collisions by making a turn
		children = Avoid_Collision_Children,
	}
}


is_blocked :: proc(creature: Creature, grid: Grid) -> bool {
	// Ensure there is nothing in the way
	front_block_pos := get_front_block(creature)
	block, block_real := get_block(grid, expand_values(front_block_pos))

	// If we're at the edge of the map or if the block is impermeable, we are blocked
	return !block_real || !is_block_permeable(block.type)
}

// Simple actions 
Steer_Away_Action :: proc(
	blackboard: ^Ant_Action_Blackboard,
) -> system.Action(Ant_Action_Blackboard) {
	return system.Action_Simple(Ant_Action_Blackboard) {
		name = "Steer away from obstacle",
		blackboard = blackboard,
		work = proc(ctx: ^Ant_Action_Blackboard) {
			creature := ctx.creature
			turn_creature(creature, Direction.Around)
			ctx.target_location = creature.pos + (creature.direction * get_random_value_f(1, 3))
		},
	}
}

Turn_Towards_Target_Action :: proc(
	blackboard: ^Ant_Action_Blackboard,
) -> system.Action(Ant_Action_Blackboard) {
	return system.Action_Simple(Ant_Action_Blackboard) {
		name = "Turn towards target",
		blackboard = blackboard,
		work = proc(ctx: ^Ant_Action_Blackboard) {
			creature := ctx.creature
			random_angle_offset := get_random_value_f(-0.05, 0.05)
			creature.direction = rl.Vector2Rotate(
				rl.Vector2Normalize(ctx.target_location - creature.pos),
				random_angle_offset,
			)
		},
	}
}

Take_Step_Action :: proc(
	blackboard: ^Ant_Action_Blackboard,
) -> system.Action(Ant_Action_Blackboard) {
	return system.Action_Simple(Ant_Action_Blackboard) {
		name = "Take a step",
		blackboard = blackboard,
		work = proc(ctx: ^Ant_Action_Blackboard) {
			creature := ctx.creature
			creature.pos += creature.direction * rl.GetFrameTime() * creature.speed
		},
	}
}

@(test)
test_walk_action :: proc(t: ^testing.T) {
	// Generate a grid for the purposes of the test
	grid := init_grid()
	defer deinit_grid(&grid)

	// Generate a rock wall 10 blocks high between the player and the target location
	for i in -5 ..< f32(5) {
		block := get_block_ptr(&grid, NEST_POS + {5, i})
		block.type = .Rock
	}

	creature := Creature {
		speed = 10,
		pos   = NEST_POS,
	}

	target_location := NEST_POS + {10, 0}

	walk_blackboard := Ant_Action_Blackboard {
		creature        = &creature,
		grid            = grid,
		target_location = target_location,
	}

	walk: system.Action(Ant_Action_Blackboard) = Walk_Action(&walk_blackboard)
	steps, succeeded := system.execute_action(walk)

	if succeeded {
		fmt.printfln("Walk succeeded, steps taken: %d", steps)
	}
	testing.expectf(
		t,
		succeeded,
		"Walk did not succeed, target position: %v, result position: %v",
		target_location,
		creature.pos,
	)
}
