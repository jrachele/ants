package ants

import "core:fmt"
import "core:math"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
Triangle :: [3]rl.Vector2

// In seconds,
ANT_AVG_LIFESPAN :: 100

when ODIN_DEBUG {
	ANT_SPAWN_RATE :: 1
} else {
	ANT_SPAWN_RATE :: 5
}
// One Ant every n seconds 

AntType :: enum {
	Peon,
	Armored,
	Porter,
	Elite,
	Queen,
}

Ant :: struct {
	pos:       rl.Vector2,
	type:      AntType,
	angle:     f32,
	health:    f32,
	life_time: f32,
	load:      f32,
	loadType:  EnvironmentType,
	state:     AntState,
}

AntMetaData :: struct {
	color:             rl.Color,
	size:              f32,
	speed:             f32,
	initial_life:      f32, // Initial life stage when spawned 
	average_life:      f32, // Average life stage until health deteriorates 
	initial_health:    f32,
	carrying_capacity: f32,
}

AntValues := [AntType]AntMetaData {
	.Peon = AntMetaData {
		size = 1,
		speed = 10,
		color = rl.BLACK,
		initial_life = -10,
		average_life = 60,
		initial_health = 5,
	},
	.Armored = AntMetaData {
		size = 3,
		speed = 3,
		color = rl.RED,
		initial_life = -20,
		average_life = 300,
		initial_health = 100,
	},
	.Porter = AntMetaData {
		size = 3,
		speed = 3,
		color = rl.GREEN,
		initial_life = -20,
		average_life = 300,
		initial_health = 30,
	},
	.Elite = AntMetaData {
		size = 15,
		speed = 10,
		color = rl.BLUE,
		initial_life = -50,
		average_life = 1000,
		initial_health = 1000,
	},
	.Queen = AntMetaData{size = 30, color = rl.DARKPURPLE},
}

AntState :: enum {
	Wander, // This is either patrol, or search
	Danger, // Whether or not the ant engages depends on the situation
	Forage, // Seeking wood, dirty, rocks, food, etc.
	Build, // Building planned projects 
	Idling, // Waiting for a second and analyzing the environment
	ReturnHome, // Returning to the queen
}

spawn_ant :: proc(queen: Ant, ants: ^[dynamic]Ant, type: AntType = AntType.Peon) {
	queen_data := AntValues[.Queen]
	ant_data := AntValues[type]
	append(
		ants,
		Ant {
			pos = queen.pos +
			rl.Vector2 {
					f32(rl.GetRandomValue(-i32(queen_data.size), i32(queen_data.size))),
					f32(rl.GetRandomValue(-i32(queen_data.size), i32(queen_data.size))),
				},
			type = type,
			angle = get_random_value_f(-math.PI, math.PI),
			health = ant_data.initial_health,
			life_time = ant_data.initial_life,
		},
	)
}

update_ants :: proc(ants: ^[dynamic]Ant) {
	// Make a decision for the ant based on its role 
	for &ant, i in ants {
		ant.life_time += rl.GetFrameTime()
		ant_data := AntValues[ant.type]
		if (ant.life_time < 0) do continue
		if (ant.life_time > ant_data.average_life) {
			ant.health -= rl.GetFrameTime()
		}

		if (ant.health < 0) {
			ordered_remove(ants, i)
			continue
		}

		// TODO: Implement behavior tree / observe environment 
		random_walk(&ant)
	}
}

random_walk :: proc(ant: ^Ant) {
	ant_data := AntValues[ant.type]
	ant.pos +=
		rl.Vector2{math.cos(ant.angle), -math.sin(ant.angle)} * rl.GetFrameTime() * ant_data.speed
	ant.angle += get_random_value_f(-math.PI / 100, math.PI / 100)
}

draw_ants :: proc(ants: []Ant) {
	for ant in ants {
		draw_ant(ant)

		mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), camera)

		ant_data := AntValues[ant.type]
		if rl.Vector2Distance(mouse_pos, ant.pos) < ant_data.size {
			draw_ant_data(ant)
		}
	}
}

// For now just draw triangles 
draw_ant :: proc(ant: Ant) {
	antTriangle := rotated_triangle(ant.angle)

	ant_data := AntValues[ant.type]
	if ant.life_time < 0 {
		rl.DrawCircleV(ant.pos, ant_data.size, rl.WHITE)
	} else {
		// The ant hasn't been born yet! draw an egg instead 
		rl.DrawTriangle(
			expand_values(translate_triangle(antTriangle, ant.pos, ant_data.size)),
			ant_data.color,
		)
	}
}

draw_queen :: proc(ant: Ant) {
	// If the queen dies, eventually a knight can take her place 
	ant_data := AntValues[ant.type]

	rl.DrawPoly(ant.pos, 7, ant_data.size, 0, ant_data.color)
}

draw_ant_data :: proc(ant: Ant) {
	sb: strings.Builder
	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	ant_data := AntValues[ant.type]
	// TODO: Draw health bar
	if ant.life_time < 0 {
		fmt.sbprintf(&sb, "%v (%.2fs)", ant.type, ant.life_time * -1.0)
	} else {
		fmt.sbprintf(&sb, "%v", ant.type)
	}

	label_str := strings.to_cstring(&sb)

	// TODO: Get different font working 
	draw_text_align(
		rl.GetFontDefault(),
		label_str,
		i32(ant.pos.x),
		i32(ant.pos.y),
		.Center,
		i32(ant_data.size),
		rl.Color{0, 0, 0, 80},
	)

}

rotated_triangle :: proc(angle: f32) -> (trianglePoints: Triangle) {
	trianglePoints = Triangle{{0, 3}, {-1, 0}, {1, 0}}

	// The actual angle used needs to be offset by 90 degrees 
	angle := angle - (math.PI / 2)

	centroid: rl.Vector2
	for point in trianglePoints {
		centroid += point
	}
	centroid /= 3.0

	for &point in trianglePoints {
		point -= centroid
	}

	cos_angle := math.cos(angle)
	sin_angle := math.sin(angle)
	rotatedPoints := trianglePoints
	for point, i in trianglePoints {
		rotatedPoints[i] =
			{
				(point.x * cos_angle) - (point.y * sin_angle),
				(point.x * sin_angle) + (point.y * cos_angle),
			} +
			centroid
	}

	trianglePoints = rotatedPoints

	return trianglePoints
}

translate_triangle :: proc(
	trianglePoints: Triangle,
	screenPosition: rl.Vector2,
	scale: f32,
) -> Triangle {
	translatedPoints: Triangle
	for i in 0 ..< 3 {
		translatedPoints[i].x = (trianglePoints[i].x * scale) + screenPosition.x
		translatedPoints[i].y = -(trianglePoints[i].y * scale) + screenPosition.y
	}
	return translatedPoints
}
