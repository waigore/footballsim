class_name AppShellPaint
extends RefCounted


var shell = null

func _init(host: Control) -> void:
	shell = host


func confirm_body() -> String:
	if shell.prev_screen == AppShell.SCREEN_NONE:
		return "The match in progress will end and the game will close."
	return "The game will close."

func draw(vp: Vector2) -> void:
	var under: String = shell.screen
	if shell.screen == AppShell.SCREEN_CONFIRM:
		under = shell.prev_screen
	if under == AppShell.SCREEN_MENU or under == AppShell.SCREEN_SETTINGS:
		draw_backdrop(vp)
		if under == AppShell.SCREEN_MENU:
			shell.menu.draw(shell, vp, shell.fonts, shell.has_match, shell.volume, shell.touch)
		else:
			shell.settings.draw(shell, vp, shell.fonts, shell.volume, shell.touch, shell.hud_visible,
				shell.match_mode)
	elif shell.screen == AppShell.SCREEN_CONFIRM:
		shell.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
	if shell.screen == AppShell.SCREEN_CONFIRM:
		shell.confirm.draw(shell, vp, shell.fonts, "QUIT FOOTBALL SIM?", confirm_body(),
			"QUIT", "CANCEL", shell.touch)

func draw_backdrop(vp: Vector2) -> void:
	if shell.stills.is_empty():
		shell.draw_rect(Rect2(Vector2.ZERO, vp), UiChrome.C_BG)
		return
	var cur: int = MenuScreen.current_still(shell.motion)
	shell.draw_texture_rect(shell.stills[cur % shell.stills.size()],
		MenuScreen.ken_rect(vp, cur, shell.motion), false)
	var a: float = MenuScreen.fade_alpha(shell.motion)
	if a > 0.001:
		var nxt: int = MenuScreen.next_still(shell.motion)
		shell.draw_texture_rect(shell.stills[nxt % shell.stills.size()],
			MenuScreen.ken_rect(vp, nxt, shell.motion), false, Color(1, 1, 1, a))
	shell.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.008, 0.014, 0.018, 0.18))
	if shell.scrim != null:
		shell.draw_texture_rect(shell.scrim, Rect2(Vector2.ZERO, vp), false)
