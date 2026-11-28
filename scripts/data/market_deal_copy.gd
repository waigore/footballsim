class_name MarketDealCopy
extends RefCounted


const STATES := {
	"proposed": "NAMED",
	"negotiating": "IN TALKS",
	"agreed": "AGREED",
	"clearance_pending": "CLEARANCE",
	"signed": "SIGNED",
	"withdrawn": "WITHDRAWN",
	"failed": "FAILED",
	"blocked": "BLOCKED",
}

const REASONS := {
	"window_closed": "THE WINDOW IS CLOSED",
	"not_at_club": "HE IS NOT AT THAT CLUB",
	"live_deal": "ANOTHER DEAL IS LIVE",
	"terms_incomplete": "THE TERMS ARE INCOMPLETE",
	"refused_consent": "THE PLAYER SAID NO",
	"no_cash": "THE BUYER CANNOT PAY",
	"ffp": "OVER THE FFP LINE",
	"list_refused": "THE LIST REFUSES HIM",
	"no_clearance": "CLEARANCE FAILED",
	"god_blocked": "BLOCKED BY GOD",
}


static func state(state: String) -> String:
	return str(STATES.get(state, state.to_upper()))


static func reason(code: String) -> String:
	if code == "":
		return ""
	return str(REASONS.get(code, code.to_upper()))
