extends SceneTree

## Logic probe for the fixture picker: cycling never picks the same club twice,
## and confirm emits the selected pair.

func _init() -> void:
	var sel := Control.new()
	sel.set_script(load("res://scripts/ui/team_select.gd"))
	get_root().add_child(sel)
	sel.setup("ARS", "LIV")
	print("start %s v %s" % [sel.home_id(), sel.away_id()])
	var ok := true
	for i in range(200):
		if i % 2 == 0:
			sel.cycle_home(1)
		else:
			sel.cycle_away(-1)
		if sel.home_id() == sel.away_id():
			ok = false
			print("DUPLICATE at %d: %s v %s" % [i, sel.home_id(), sel.away_id()])
			break
	print("cycle unique: %s" % str(ok))
	sel.setup("ARS", "LIV")
	sel.key(KEY_RIGHT)
	sel.key(KEY_UP)
	print("after keys %s v %s" % [sel.home_id(), sel.away_id()])
	var got := []
	sel.confirmed.connect(func(h, a): got.append([h, a]))
	sel.confirm()
	print("confirm emitted %s" % str(got))
	var cancel_hit := [false]
	sel.cancelled.connect(func(): cancel_hit[0] = true)
	sel.key(KEY_ESCAPE)
	print("escape cancelled: %s" % str(cancel_hit[0]))
	quit()
