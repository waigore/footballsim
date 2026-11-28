extends RefCounted


signal event_fired(e: Dictionary)
signal ball_kicked(strength: float)

const L := 105.0
const W := 68.0
const GOAL_W := 7.32
const GOAL_H := 2.44
const BOX_D := 16.5
const BOX_W := 40.32
const SIX_D := 5.5
const SIX_W := 18.32
const PEN_D := 11.0
const CENTER := Vector2(52.5, 34.0)
const DT := 1.0 / 60.0

const FAST_FORWARD_TICKS := 60 * 60 * 200


const REF_TRAIL := 12.0
const REF_SIDE := 6.5
const REF_JOG := 7.6
const REF_SPRINT := 8.8


const HANDBALL_P := 0.055


const SUB_WINDOWS := 3
const SUB_LIMIT := 5

class Player:
	var id := 0


	var key := ""
	var team := 0
	var name := ""
	var number := 0
	var role := ""
	var pos_label := ""
	var attr := {}
	var gk := {}
	var base := Vector2.ZERO
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var facing := Vector2.RIGHT
	var target := Vector2.ZERO
	var speed_scale := 1.0
	var stamina := 1.0
	var z := 0.0
	var state := "idle"
	var action_t := 0.0
	var cooldown := 0.0
	var has_ball := false
	var yellow := 0
	var red := false
	var sent_off := false
	var injured := false
	var is_gk := false
	var dive := Vector2.ZERO
	var dive_t := 0.0
	var jump_t := 0.0
	var celebrate := 0.0
	var offside_flag := false
	var mark_id := -1
	var run_until := 0.0
	var run_to := Vector2.ZERO


	var spd_max := 0.0
	var acc := 0.0
	var dri_speed := 0.0
	var ctrl_radius := 0.0
	var drain_phy := 0.0
	var aerial := 0.0
	var _sep_idx := 0

	var stats := {
		"passes": 0, "passes_ok": 0, "shots": 0, "on_target": 0, "goals": 0,
		"assists": 0, "tackles": 0, "interceptions": 0, "fouls": 0, "saves": 0,
		"touches": 0, "distance": 0.0, "rating": 6.0,
	}
	var involvements := []
	var trail := []
	var trail_t := 0.0
	var last_action := ""
	var active := true
	var _surname := ""


	func surname_text() -> String:
		if _surname == "":
			var bits: PackedStringArray = String(name).split(" ")
			_surname = bits[bits.size() - 1].to_upper()
		return _surname

class Ball:
	var pos := Vector2(52.5, 34.0)
	var vel := Vector2.ZERO
	var z := 0.0
	var vz := 0.0
	var spin := 0.0
	var owner_id := -1
	var last_touch_id := -1
	var last_touch_team := -1
	var last_kick_id := -1
	var assist_id := -1
	var assist_time := -10.0
	var shot_team := -1
	var shot_time := -10.0
	var shot_xg := 0.0
	var last_touch_time := -10.0
	var shot_saved := false
	var planned_goal := false
	var loose_t := 0.0


class Official:
	var pos = Vector2(52.5, 24.0)
	var vel = Vector2.ZERO
	var facing = Vector2.RIGHT
	var whistle = 0.0
	var focus = Vector2.ZERO
	var focus_t = 0.0

var rng = RandomNumberGenerator.new()
var home_team := 0
var home_advantage := 0.05
var seed_value = 4242

var teams: Array = []
var players: Array = []
var appeared: Array = []
var by_id: Dictionary = {}
var ball = Ball.new()
var referee = Official.new()
var referee_name: String = TeamData.REFEREE
var brain = null
var manager = null
var live_style: Array = [{}, {}]
var stoppage_seq := 0

var clock = 0.0
var half = 1
var phase = "play"
var restart: Dictionary = {}
var restart_timer = 0.0

var added: Array = [0.0, 0.0, 0.0, 0.0]


var requires_winner := false

var winner := -1
var kickoff_team = 0
var possession_team = 0
var possession_loose = true
var score: Array = [0, 0]
var stats: Array = []
var events: Array = []
var ev_seq = 0
var sim_tick = 0
var goal_timer = 0.0
var last_goal: Dictionary = {}
var finished = false
var half_break_timer = 0.0
var momentum: Array = [0.0, 0.0]
var last_pass_time = 0.0
var flash = 0.0
var stoppage_events = 0
var injury_timer := 45.0
var commentary_key = 0
var verbose := false
var shot_buckets := {}
var gk_debug := []


var _sep_x := PackedFloat64Array()
var _sep_y := PackedFloat64Array()
var _sep_count := 0


var _squad_rev := 0
var _team_cache := [[], []]
var _team_cache_rev := -1


func _fill_attr_cache(p: Player) -> void:
	var phy: float = float(p.attr["phy"])
	p.spd_max = Attrs.max_speed(p)
	p.acc = Attrs.accel(p)
	p.dri_speed = Attrs.dribble_speed(p)
	p.ctrl_radius = Attrs.control_radius(p)
	p.drain_phy = 1.25 - phy / 100.0 * 0.45
	p.aerial = Attrs.aerial(p)


func _gk_of(t: int):
	for p in players:
		if p.team == t and p.is_gk and not p.sent_off:
			return p
	return null


func _last_kicker_name(not_team: int) -> String:
	var k = by_id.get(ball.last_kick_id, null)
	if k == null or k.team == not_team:
		return ""
	return k.name

func _shot_credit(gk) -> String:
	return _last_kicker_name(gk.team)
