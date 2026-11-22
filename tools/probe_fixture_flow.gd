extends SceneTree

## End-to-end fixture flow: selector at launch -> cycle -> confirm -> engine teams.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game = scene.instantiate()
	get_root().add_child(game)
	print("launch select_open=%s fixture=%s v %s" % [str(game.select_open), game.home_id, game.away_id])
	game.selector.cycle_home(1)
	game.selector.cycle_away(1)
	var picked_h: String = game.selector.home_id()
	var picked_a: String = game.selector.away_id()
	game.selector.confirm()
	print("picked %s v %s" % [picked_h, picked_a])
	print("confirmed select_open=%s state=%s v %s engine=%s v %s" % [
		str(game.select_open), game.home_id, game.away_id,
		game.engine.teams[0]["id"], game.engine.teams[1]["id"]])
	print("hud_visible=%s sel_visible=%s paused=%s" % [
		str(game.hud_layer.visible), str(game.sel_layer.visible), str(game.paused)])
	game.open_select()
	game.selector.cycle_home(1)
	game.selector.key(KEY_ESCAPE)
	print("cancelled state=%s v %s engine=%s v %s open=%s" % [
		game.home_id, game.away_id, game.engine.teams[0]["id"], game.engine.teams[1]["id"],
		str(game.select_open)])
	quit()
