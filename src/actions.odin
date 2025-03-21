package ants

import sm "core:container/small_array"
import "core:fmt"
import "core:io"
import "core:math"
import "core:testing"
import "core:time"
import rl "vendor:raylib"

ACTION_STACK_SIZE :: 64

Action_Stack :: sm.Small_Array(ACTION_STACK_SIZE, Action)

Action_Status :: enum {
	Running,
	Failed,
	Succeeded,
}

peek_current_action :: proc(entity: Entity) -> (Action, bool) {
	return sm.get_safe(entity.actions, sm.len(entity.actions) - 1)
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
	case Action_Wait:
		_wait(entity, action)
	case Action_Haul:
	case Action_Find:
	case Action_Return:
	}

	return .Running
}


Action :: union {
	Action_Walk,
	Action_Find,
	Action_Haul,
	Action_Return,
	Action_Wait,
}

fmt_action :: proc(w: io.Writer, action: Action) -> int {
	switch a in action {
	case Action_Walk:
		return fmt.wprintfln(w, "Walking to (%.2f, %.2f)", a.walk_to.x, a.walk_to.y)
	case Action_Find:
		return fmt.wprintfln(w, "Finding %s", a.item)
	case Action_Haul:
		return fmt.wprintfln(w, "Hauling %s", a.item)
	case Action_Return:
		return fmt.wprintfln(w, "Returning home")
	case Action_Wait:
		return fmt.wprintfln(w, "Waiting (%.2fs)", a.remaining_time)
	}
	return 0
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

Action_Wait :: struct {
	remaining_time: f32,
}

get_local_neighborhood :: proc(
	entity: Entity,
	grid: Grid,
) -> (
	local_neighborhood: [9]EnvironmentType,
) {
	block_position := to_block_position(entity.pos)
	for i in 0 ..< 9 {
		ox := i32(i % 3) - 1
		oy := i32(i / 3) - 1
		position := block_position + {ox, oy}
		index := to_index(position)
		if block, exists := get_block(grid, index); exists {
			local_neighborhood[i] = block.type
		} else {
			local_neighborhood[i] = .Nothing
		}
	}
	return
}

_walk :: proc(entity: ^Entity, walk_action: Action_Walk) -> bool {
	using walk_action

	// TODO: Maybe store entity size as a variable
	// Early out if we have reached our destination
	if rl.Vector2Distance(entity.pos, walk_to) < 1 {
		return true
	}

	entity.direction = rl.Vector2Normalize(walk_to - entity.pos)
	velocity := rl.Vector2Normalize(entity.direction) * entity.speed

	repellent_force: rl.Vector2
	REPELLENT_STRENGTH :: 100
	// Ensure we avoid collisions by being repelled by blocks in our local neighborhood 
	local_neighborhood := get_local_neighborhood(entity^, environment^)
	for i in 0 ..< 9 {
		ox := i32(i % 3) - 1
		oy := i32(i / 3) - 1

		// Ignore the block the entity is on
		if ox == 0 && oy == 0 do continue

		block_type := local_neighborhood[i]
		block_position := to_block_position(entity.pos) + {ox, oy}
		world_position :=
			to_world_position(block_position) + {GRID_CELL_SIZE / 2, GRID_CELL_SIZE / 2}
		// Avoid impermeable blocks 
		if !is_block_permeable(block_type) {
			block_distance := rl.Vector2Distance(world_position, entity.pos)
			if block_distance > 0 {
				block_direction := rl.Vector2Normalize(entity.pos - world_position)
				force := REPELLENT_STRENGTH / (block_distance * block_distance)
				repellent_force += block_direction * force
			}
		}
	}


	dt := rl.GetFrameTime()
	when ODIN_TEST {
		dt = f32(1.0 / 60.0)
	}
	velocity = velocity + repellent_force
	entity.direction = rl.Vector2Normalize(velocity)
	entity.pos += velocity * dt

	// If we haven't yet reached the destination, requeue the walk action
	if rl.Vector2Distance(entity.pos, walk_to) >= 1 {
		return queue_action(entity, walk_action)
	}


	// if is_blocked(entity^, environment^) {
	// 	// The walking is incomplete, so push the current walk back onto the stack
	// 	queue_action(entity, walk_action)

	// 	// Pick a new random location to walk to         
	// 	offset := get_random_value_f(math.PI / 6, math.PI / 4)
	// 	offset *= flip_coin() ? -1 : 1
	// 	new_direction := rl.Vector2Rotate(entity.direction, offset)
	// 	new_location := entity.pos + (new_direction * get_random_value_f(1, 3))

	// 	// Really, I need to snap to the nearest 90 degree angle (but organically)


	// 	avoid_collision := Action_Walk {
	// 		environment = environment,
	// 		walk_to     = new_location,
	// 	}
	// 	// Recur into another walk action to avoid the collision
	// 	return queue_action_sequence(
	// 		entity,
	// 		// Also wait briefly
	// 		{Action_Wait{remaining_time = get_random_value_f(0, 0.2)}, avoid_collision},
	// 	)
	// } else {
	// }

	return true
}

_wait :: proc(entity: ^Entity, wait_action: Action_Wait) {
	wait_action := wait_action
	dt := rl.GetFrameTime()
	when ODIN_TEST {
		dt = f32(1.0 / 60.0)
	}
	wait_action.remaining_time -= dt

	// If we're still waiting, requeue the wait action with the new time
	if wait_action.remaining_time > 0 {
		queue_action(entity, wait_action)
	}
}

@(test)
test_walk_action :: proc(t: ^testing.T) {
	// Generate a grid for the purposes of the test
	grid := init_grid()
	for &block in grid.data {
		block = {}
	}
	defer deinit_grid(&grid)

	// Generate a rock wall 10 blocks high between the player and the target location
	for i in -5 ..< f32(5) {
		block := get_block_ptr_from_world_position(&grid, NEST_POS + {5, i})
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

	timer: time.Stopwatch
	time.stopwatch_start(&timer)

	TEST_TIMEOUT :: 30 * time.Second

	for status == Action_Status.Running && time.stopwatch_duration(timer) < TEST_TIMEOUT {
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
