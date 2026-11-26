extends RefCounted

## Match state base of the MatchEngine chain: constants, the Player/Ball/
## Official shapes, the flat separation arrays the movement pass writes, and the
## per-player derived-attribute cache. Each split file adds one layer: squad
## reads, pitch geometry, presentation, duels, actions, play, rules, clock, then
## the restarts leaf in match_engine.gd.

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
## `run_to_full_time` ceiling: 200 match minutes so a stuck phase cannot spin forever.
const FAST_FORWARD_TICKS := 60 * 60 * 200

## Dead-ball judgement lives in MatchRestarts (READY_RADIUS, SETTLED_SPEED,
## WAIT_STEP); the restart lane only places bodies and picks taker + target.

## Referee movement: he runs the opposite side of the diagonal to the ball,
## a dozen metres behind it, and closes on the spot when play stops.
const REF_TRAIL := 12.0
const REF_SIDE := 6.5
const REF_JOG := 7.6
const REF_SPRINT := 8.8

## Share of shot blocks that are really an arm in the flight path.
const HANDBALL_P := 0.055

## IFAB substitution limits: five changes, three windows, half-time free.
const SUB_WINDOWS := 3
const SUB_LIMIT := 5

class Player:
	var id := 0
	## Stable snapshot key ("MUN-b-fernandes"): survives a re-slot and is what
	## in-sim stats are stored against.
	var key := ""
	var team := 0
	var name := ""
	var number := 0
	var role := ""
	var pos_label := ""
	var attr := {}
	var gk := {}
	var base := Vector2.ZERO       # normalized formation slot in attacking frame
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
	# Derived-attribute cache, filled once at squad build (Attrs math is fixed
	# per player). Keeps per-tick movement free of dictionary lookups and pow().
	var spd_max := 0.0        # Attrs.max_speed
	var acc := 0.0            # Attrs.accel
	var dri_speed := 0.0      # Attrs.dribble_speed
	var ctrl_radius := 0.0    # Attrs.control_radius
	var drain_phy := 0.0      # (1.25 - phy/100 * 0.45) factor of Attrs.stamina_drain
	var aerial := 0.0         # Attrs.aerial
	var _sep_idx := 0         # index in the engine's flat separation arrays

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

	## Last word of the name, upper-cased. Cached: the overlay draws 22 tokens
	## every frame and splitting a string 22 times a frame is phone-garbage.
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
	var planned_goal := false  # this on-target shot has already beaten the keeper
	var planned_save := false  # this chance will not convert: the keeper stops it
	var loose_t := 0.0

## The match official. Presentation only: laws are decided by the engine, but
## the referee has a body on the pitch, a position that follows play and a
## whistle that fires on restarts, cards and disciplinary calls.
class Official:
	var pos = Vector2(52.5, 24.0)
	var vel = Vector2.ZERO
	var facing = Vector2.RIGHT
	var whistle = 0.0          # presentation: seconds of whistle / arm-raise left
	var focus = Vector2.ZERO   # where play stopped (foul spot, kick-off spot)
	var focus_t = 0.0

var rng = RandomNumberGenerator.new()
var home_team := 0
var home_advantage := 0.05   # +5% composure/duels for the home side
var seed_value = 4242

var teams: Array = []
var players: Array = []
var by_id: Dictionary = {}
var ball = Ball.new()
var referee = Official.new()
var referee_name: String = TeamData.REFEREE
var brain = null  # MatchAI: the pitch
var manager = null  # MatchManager: the dugout
var live_style: Array = [{}, {}]  # effective tactics style per side, refreshed on change
var stoppage_seq := 0  # dead-ball counter; subs in the same stoppage share a window

var clock = 0.0
var half = 1
var phase = "play"                 # play, restart, goal, half_time, full_time
var restart: Dictionary = {}
var restart_timer = 0.0
var added: Array = [0.0, 0.0]
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
var flash = 0.0                   # presentation hint: 0..1
var stoppage_events = 0
var injury_timer := 45.0
var commentary_key = 0
var verbose := false
var shot_buckets := {}
var gk_debug := []

# Flat separation arrays (float64 to keep position arithmetic exact), rebuilt
# once per _move_players pass; see match_engine_play.gd.
var _sep_x := PackedFloat64Array()
var _sep_y := PackedFloat64Array()
var _sep_count := 0

# Squad revision: bumped whenever the players array or a sent-off flag changes,
# so per-tick caches derived from the squad can invalidate themselves. The
# team cache that reads it lives one layer up in match_engine_squad.gd.
var _squad_rev := 0
var _team_cache := [[], []]
var _team_cache_rev := -1

# Sorted descending attacking-x per side, cached per sim tick: state lives in
# the pitch layer (match_engine_pitch.gd) next to attacking_x.

## Per-player derived-attribute cache: the Attrs mappings are fixed once the
## attributes exist, so pay the dictionary reads and pow() once per squad.
func _fill_attr_cache(p: Player) -> void:
	var phy: float = float(p.attr["phy"])
	p.spd_max = Attrs.max_speed(p)
	p.acc = Attrs.accel(p)
	p.dri_speed = Attrs.dribble_speed(p)
	p.ctrl_radius = Attrs.control_radius(p)
	p.drain_phy = 1.25 - phy / 100.0 * 0.45
	p.aerial = Attrs.aerial(p)

# ---------------------------------------------------------------- lifecycle --

func _gk_of(t: int):
	for p in players:
		if p.team == t and p.is_gk and not p.sent_off:
			return p
	return null

## Shooter name unless the ball was last kicked by the stopping side.
func _last_kicker_name(not_team: int) -> String:
	var k = by_id.get(ball.last_kick_id, null)
	if k == null or k.team == not_team:
		return ""
	return k.name

func _shot_credit(gk) -> String:
	return _last_kicker_name(gk.team)
