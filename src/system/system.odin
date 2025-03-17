package system

import "core:fmt"
import "core:testing"
import "core:time"
import rl "vendor:raylib"


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
	children:       []Action(Blackboard),

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

DEFAULT_ACTION_TIMEOUT :: 1 * time.Second
DEFAULT_ACTION_MAX_DEPTH :: 64

update_action :: proc(action_base: Action($T), blackboard: ^T, depth := 0) -> Action_Status {
	if depth >= DEFAULT_ACTION_MAX_DEPTH {
		return .Failed
	}

	// TODO: Use a stack and do it iteratively instead of recursively potentially
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
			if len(action.children) == 0 {
				return .Failed
			}

			for sub_action in action.children {
				// Go through as many sub actions as possible, earlying out if we fail or are pending
				switch update_action(sub_action, blackboard, depth + 1) {
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

// Executes an action synchronously, returning true if it succeeded, and false if it failed or timed out
execute_action :: proc(
	action: Action($T),
	blackboard: ^T,
	timeout := DEFAULT_ACTION_TIMEOUT,
) -> bool {
	status := Action_Status.Pending
	stopwatch := time.Stopwatch{}
	time.stopwatch_start(&stopwatch)
	for status == .Pending {
		status = update_action(action, blackboard)

		if time.stopwatch_duration(stopwatch) >= DEFAULT_ACTION_TIMEOUT {
			fmt.eprintfln("Action timed out! %v", action)
			status = .Failed
		}
	}

	return status == .Succeeded
}
