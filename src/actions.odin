package ants

import "core:testing"
import "system"
import rl "vendor:raylib"

Walk_Blackboard :: struct {
	creature:        ^Creature,
	grid:            Grid,
	target_location: rl.Vector2,
}

Walk_Action := system.Action_Complex(Walk_Blackboard) {
	pre_condition = proc(bb: ^Walk_Blackboard) -> bool {
		return rl.Vector2Distance(bb.creature.pos, bb.target_location) > 1
	},
	post_condition = proc(bb: ^Walk_Blackboard) -> bool {
		return rl.Vector2Distance(bb.creature.pos, bb.target_location) < 1
	},
	children = {Turn_Action, Take_Step_Action},
}

Avoid_Collision_Action := system.Action_Complex(Walk_Blackboard) {
	pre_condition = proc(bb: ^Walk_Blackboard) -> bool {
		return is_blocked(bb.creature^, bb.grid)
	},
	post_condition = proc(bb: ^Walk_Blackboard) -> bool {
		return !is_blocked(bb.creature^, bb.grid)
	},
	// Avoid collisions by making a turn
	// TODO: We want to be able to have separate contexts injected into child actions 
}

is_blocked :: proc(creature: Creature, grid: Grid) -> bool {
	// Ensure there is nothing in the way
	front_block_pos := get_front_block(creature)
	block, block_real := get_block(grid, expand_values(front_block_pos))

	// If we're at the edge of the map or if the block is impermeable, we are blocked
	return !block_real || !is_block_permeable(block.type)
}


Turn_Action := system.Action_Simple(Walk_Blackboard) {
	work = proc(ctx: ^Walk_Blackboard) {
		creature := ctx.creature
		random_angle_offset := get_random_value_f(-0.05, 0.05)
		creature.direction = rl.Vector2Rotate(
			rl.Vector2Normalize(ctx.target_location - creature.pos),
			random_angle_offset,
		)
	},
}

Take_Step_Action := system.Action_Simple(Walk_Blackboard) {
	work = proc(ctx: ^Walk_Blackboard) {
		creature := ctx.creature
		creature.pos += creature.direction * 0.18 * creature.speed
	},
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

	walk_blackboard := Walk_Blackboard {
		creature        = &creature,
		target_location = NEST_POS + {10, 0},
	}
	walk: system.Action(Walk_Blackboard) = Walk_Action
	succeeded := system.execute_action(walk, &walk_blackboard)
	testing.expectf(t, succeeded, "Walk did not succeed!")
}
