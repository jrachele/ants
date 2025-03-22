package ants

import clay "clay-odin"
import "core:fmt"
import rl "vendor:raylib"

STANDARD :: 4
HOVERED :: 3
HELD :: 2

Button_Color :: COLORS_BLUE[STANDARD]
Button_Hovered_Color :: COLORS_BLUE[HOVERED]
Button_Held_Color :: COLORS_BLUE[HELD]
Button :: proc(text: string, pressed: ^bool, icon: string = "") {
	using clay

	button_id := clay.ID(text)
	hovering := clay.PointerOver(button_id)

	held := hovering && rl.IsMouseButtonDown(.LEFT)
	pressed^ = hovering && rl.IsMouseButtonPressed(.LEFT)

	background_color := Button_Color
	if held {
		background_color = Button_Held_Color
	} else if hovering {
		background_color = Button_Hovered_Color
	}

	if clay.UI()(
	ElementDeclaration {
		id = button_id,
		backgroundColor = background_color,
		cornerRadius = CornerRadiusAll(8.0),
		layout = {
			sizing = {height = SizingFit({}), width = SizingFit({})},
			padding = PaddingAll(8),
			childAlignment = {x = .Center, y = .Center},
			childGap = 16,
			layoutDirection = .LeftToRight,
		},
	},
	) {
		if (icon != "") {
			Text(
				icon,
				TextConfig(
					{
						fontSize = 18,
						textColor = COLORS_GRAY[9],
						textAlignment = .Center,
						fontId = u16(Fonts.Icon),
					},
				),
			)
		}
		Text(
			text,
			TextConfig(
				{
					fontSize = 18,
					textColor = COLORS_GRAY[9],
					textAlignment = .Center,
					fontId = u16(Fonts.SansSerif),
				},
			),
		)
	}
}

Slider :: proc(value: ^f32, min: f32 = 0, max: f32 = 1, label: string = "") {
	using clay

	slider_id := clay.ID(fmt.aprintf("Slider##%s", label))
	knob_id := clay.ID(fmt.aprintf("SliderKnob##%s", label))
	hovering := clay.PointerOver(knob_id)

	held := hovering && rl.IsMouseButtonDown(.LEFT)

	background_color := Button_Color
	if held {
		background_color = Button_Held_Color
	} else if hovering {
		background_color = Button_Hovered_Color
	}

	if clay.UI()(
	ElementDeclaration {
		id = slider_id,
		cornerRadius = CornerRadiusAll(8.0),
		// backgroundColor = background_color,
		layout = {
			sizing = {height = SizingFit({}), width = SizingGrow({})},
			// padding = PaddingAll(8),
			// childAlignment = {x = .Center, y = .Center},
			// childGap = 16,
			layoutDirection = .LeftToRight,
		},
	},
	) {
		if clay.UI()(
		ElementDeclaration {
			layout = {sizing = {height = clay.SizingFixed(10), width = SizingGrow({min = 50})}},
			backgroundColor = background_color,
		},
		) {}
		// Text(
		// 	label,
		// 	TextConfig(
		// 		{
		// 			fontSize = 18,
		// 			textColor = COLORS_GRAY[9],
		// 			textAlignment = .Center,
		// 			fontId = u16(Fonts.SansSerif),
		// 		},
		// 	),
		// )
	}
}
