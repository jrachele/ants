// TODO: Perhaps this can be its own package 
package ants

import "core:fmt"
import "core:testing"
import rl "vendor:raylib"

Action_Complex :: struct($Blackboard: typeid) {
	// Must qualify for the pre-condition for the action to occur
	pre_condition:  proc(_: ^Blackboard) -> bool,

	// Action is complete when the post-condition is true.
	post_condition: proc(_: ^Blackboard) -> bool,

	// Actions can consist of subactions 
	sub_actions:    []proc() -> Action(Blackboard),

	// The status of the current action
	status:         Action_Status,
}

Action_Simple :: struct($Blackboard: typeid) {
	// This function will perform actual work on the mutable blackboard
	work: proc(_: ^Blackboard),
}

Action :: union($Blackboard: typeid) {
	Action_Simple(Blackboard),
	Action_Complex(Blackboard),
}

// Running actions
Action_Status :: enum {
	Pending,
	Succeeded,
	Failed, // Could potentially get rid of this and just have pending and complete
}

run_action :: proc(action: Action($T), blackboard: ^T) -> Action_Status {
	switch a in action {
	case Action_Simple(T):
		a.work(blackboard)
		return .Succeeded
	case Action_Complex(T):
		// Do an early out check here
		if a.post_condition(blackboard) {
			return .Succeeded
		}
		if a.pre_condition(blackboard) {
			// This should not be the case if the post condition is not met 
			if len(a.sub_actions) == 0 {
				return .Failed
			}

			for sub_action_generator in a.sub_actions {
				// Go through as many sub actions as possible, earlying out if we fail or are pending
				sub_action := sub_action_generator()
				switch run_action(sub_action, blackboard) {
				case .Failed:
					return .Failed
				case .Pending:
					return .Pending
				case .Succeeded:
				// Keep going through more sub-actions
				}
			}
		}
	}

	return .Pending
}

Walk_Blackboard :: struct {
	creature:        ^Creature,
	target_location: rl.Vector2,
}

Walk_Action :: proc() -> (action: Action(Walk_Blackboard)) {
	action_complex := Action_Complex(Walk_Blackboard) {
		pre_condition = proc(bb: ^Walk_Blackboard) -> bool {
			return rl.Vector2Distance(bb.creature.pos, bb.target_location) > 1
		},
		post_condition = proc(bb: ^Walk_Blackboard) -> bool {
			return rl.Vector2Distance(bb.creature.pos, bb.target_location) < 1
		},
		sub_actions = {Turn_Action, Take_Step_Action},
	}

	action = action_complex
	return
}

Turn_Action :: proc() -> Action(Walk_Blackboard) {
	return Action_Simple(Walk_Blackboard){work = proc(ctx: ^Walk_Blackboard) {
			creature := ctx.creature
			random_angle_offset := get_random_value_f(-0.05, 0.05)
			creature.direction = rl.Vector2Rotate(
				rl.Vector2Normalize(ctx.target_location - creature.pos),
				random_angle_offset,
			)
		}}
}

Take_Step_Action :: proc() -> Action(Walk_Blackboard) {
	return Action_Simple(Walk_Blackboard){work = proc(ctx: ^Walk_Blackboard) {
			creature := ctx.creature
			creature.pos += creature.direction * rl.GetFrameTime() * creature.speed
		}}
}

@(test)
test_action_system :: proc(t: ^testing.T) {
	creature := Creature {
		direction = {1, 0},
	}

	walk_blackboard := Walk_Blackboard {
		creature        = &creature,
		target_location = {5, 5},
	}
	fmt.printfln("Creature ")
	walk := Walk_Action()
	status := run_action(walk, &walk_blackboard)
	for status == .Pending {
		status = run_action(walk, &walk_blackboard)
	}
	testing.expectf(t, status == .Succeeded, "Status did not succeed!")
}
