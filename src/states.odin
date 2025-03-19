package ants

import sm "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:testing"
import rl "vendor:raylib"

Action :: union {
	Action_Walk,
	Action_Find,
	Action_Haul,
	Action_Return,
}

Action_Walk :: struct {
	environment: ^Grid,
	walk_to:     rl.Vector2,
}

Action_Find :: struct {
	environment: ^Grid,
	item:        EnvironmentType,
}

Action_Haul :: struct {
	environment: ^Grid,
	item:        EnvironmentType,
}

Action_Return :: struct {
	environment: ^Grid,
}

ACTION_STACK_SIZE :: 64

Action_Stack :: sm.Small_Array(ACTION_STACK_SIZE, Action)

Action_Status :: enum {
	Running,
	Failed,
	Succeeded,
}

tick :: proc(entity: ^Entity) -> Action_Status {
	stack := &entity.actions

	if stack == nil do return .Failed
	if sm.len(stack^) == 0 do return .Succeeded

	// Pop the action off the stack and then pass the stack itself to the action, to 
	// either put it back on (in case the action needs more time)
	// or potentially spawn more actions
	action_base := sm.pop_back(stack)
	switch &action in action_base {
	case Action_Walk:
		if !_walk(entity, action) do return .Failed
	case Action_Haul:
	case Action_Find:
	case Action_Return:
	}

	return .Running
}

has_no_actions :: proc(entity: Entity) -> bool {
	return sm.len(entity.actions) == 0
}

queue_action :: proc(entity: ^Entity, action: Action) -> bool {
	stack := &entity.actions
	if sm.len(stack^) == sm.cap(stack^) {
		return false
	}

	sm.push_back(stack, action)
	return true
}

queue_action_sequence :: proc(entity: ^Entity, actions: []Action) -> bool {
	#reverse for action in actions {
		if !queue_action(entity, action) {
			return false
		}
	}

	return true
}

is_blocked :: proc(entity: Entity, grid: Grid) -> bool {
	// Ensure there is nothing in the way
	front_block_pos := get_front_block(entity)
	block, block_real := get_block(grid, expand_values(front_block_pos))

	// If we're at the edge of the map or if the block is impermeable, we are blocked
	return !block_real || !is_block_permeable(block.type)
}

_walk :: proc(entity: ^Entity, walk_action: Action_Walk) -> bool {
	using walk_action

	// TODO: Maybe store entity size as a variable
	// Early out if we have reached our destination
	if rl.Vector2Distance(entity.pos, walk_to) < 1 {
		return true
	}

	direction := rl.Vector2Normalize(walk_to - entity.pos)
	turn_entity(entity, direction)
	if is_blocked(entity^, environment^) {
		// The walking is incomplete, so push the current walk back onto the stack
		queue_action(entity, walk_action)

		// Pick a new random location to walk to         
		offset := get_random_value_f(math.PI / 6, math.PI / 2)
		offset *= flip_coin() ? -1 : 1
		new_direction := rl.Vector2Rotate(entity.direction, offset)
		new_location := entity.pos + (new_direction * get_random_value_f(1, 3))

		avoid_collision := Action_Walk {
			environment = environment,
			walk_to     = new_location,
		}
		// Recur into another walk action to avoid the collision
		return queue_action(entity, avoid_collision)
	} else {
		dt := rl.GetFrameTime()
		when ODIN_TEST {
			dt = f32(1.0 / 60.0)
		}
		entity.pos += entity.direction * entity.speed * dt

		// If we haven't yet reached the destination, requeue the walk action
		if rl.Vector2Distance(entity.pos, walk_to) >= 1 {
			return queue_action(entity, walk_action)
		}
	}

	return true
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

	entity := Entity {
		speed = 10,
		pos   = NEST_POS,
	}

	target_location := NEST_POS + {10, 0}

	walk := Action_Walk {
		environment = &grid,
		walk_to     = target_location,
	}

	queue_action(&entity, walk)
	status := Action_Status.Running

	for status == Action_Status.Running {
		status = tick(&entity)
	}

	testing.expectf(
		t,
		status == .Succeeded,
		"Walk did not succeed, target position: %v, result position: %v",
		target_location,
		entity.pos,
	)
}
