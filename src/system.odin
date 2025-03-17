// TODO: Perhaps this can be its own package 
package ants

import sm "core:container/small_array"
import "core:fmt"
import "core:testing"
import rl "vendor:raylib"


SYSTEM_MAX_SUBACTIONS :: 64

Action_Simple :: struct($Blackboard: typeid) {
	// This function will perform actual work on the mutable blackboard
	work: proc(_: ^Blackboard),
}

Action_Complex :: struct($Blackboard: typeid) {
	// Must qualify for the pre-condition for the action to occur
	pre_condition:  proc(_: ^Blackboard) -> bool,

	// Action is complete when the post-condition is true.
	post_condition: proc(_: ^Blackboard) -> bool,

	// Actions can have child actions that must be called to satisfy the main action
	children:       sm.Small_Array(SYSTEM_MAX_SUBACTIONS, proc() -> Action(Blackboard)),

	// The status of the current action
	status:         Action_Status,
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

run_action :: proc(action_generator: proc() -> Action($T), blackboard: ^T) -> Action_Status {
	action_base := action_generator()
	switch action in action_base {
	case Action_Simple(T):
		// Just execute the action with the given blackboard
		action.work(blackboard)
		return .Succeeded
	case Action_Complex(T):
		// Ensure the conditions are satisfied and run sub-actions
		if action.post_condition(blackboard) {
			return .Succeeded
		}
		if action.pre_condition(blackboard) {
			// This should not be the case if the post condition is not met 
			if sm.len(action.children) == 0 {
				return .Failed
			}

			for i in 0 ..< sm.len(action.children) {
				sub_action := sm.get(action.children, i)

				// Go through as many sub actions as possible, earlying out if we fail or are pending
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
	}

	sm.append(&action_complex.children, Turn_Action)
	sm.append(&action_complex.children, Take_Step_Action)

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
			creature.pos += creature.direction * 0.18 * creature.speed
		}}
}

@(test)
test_action_system :: proc(t: ^testing.T) {
	creature := Creature {
		direction = {1, 0},
		speed     = 10,
	}

	walk_blackboard := Walk_Blackboard {
		creature        = &creature,
		target_location = {5, 5},
	}
	fmt.printfln("Creature ")
	status := run_action(Walk_Action, &walk_blackboard)
	for status == .Pending {
		status = run_action(Walk_Action, &walk_blackboard)
	}
	testing.expectf(t, status == .Succeeded, "Status did not succeed!")
}
