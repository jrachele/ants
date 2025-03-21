package ants

import clay "clay-odin"
import rl "vendor:raylib"

STANDARD :: 4
HOVERED :: 3
HELD :: 2

Button_Color :: COLORS_BLUE[STANDARD]
Button_Hovered_Color :: COLORS_BLUE[HOVERED]
Button_Held_Color :: COLORS_BLUE[HELD]
Button :: proc(text: string, pressed: ^bool) {
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
			layoutDirection = .LeftToRight,
		},
	},
	) {
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
