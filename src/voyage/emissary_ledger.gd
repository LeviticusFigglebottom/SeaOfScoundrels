class_name EmissaryLedger
extends RefCounted
## Host-authoritative Sea-of-Thieves Trading Company Emissary Grade ledger.
##
## Tracks an active Emissary flag for one of the three canonical Trading Companies
## (`&"gilded_compass"`, `&"sunken_archive"`, `&"iron_tide"`), advancing from Grade I
## through Grade V as the crew completes voyages, unearths/boards/sells loot, and
## vanquishes threats. Higher grades multiply matching company gold & renown payouts
## (1.00x -> 2.50x) and grant lucrative outpost cash-out bonuses when lowered, while
## raising WorldDirector hunter risk and dropping a salvageable broken flag if sunk.

signal flag_raised(company_id: StringName)
signal grade_changed(company_id: StringName, new_grade: int, multiplier: float)
signal flag_lowered(company_id: StringName, final_grade: int, bonus_gold: int, bonus_renown: int)
signal flag_broken(company_id: StringName, lost_grade: int)

const MAX_GRADE := 5
const OFF_COMPANY_XP_FACTOR := 0.55

const VALID_COMPANIES: Array[StringName] = [
	&"gilded_compass",
	&"sunken_archive",
	&"iron_tide",
]

const GRADE_XP_THRESHOLDS: Array[float] = [0.0, 100.0, 260.0, 480.0, 760.0]
const GRADE_MULTIPLIERS: Array[float] = [1.0, 1.0, 1.33, 1.67, 2.0, 2.5]
const LOWER_BONUS_GOLD: Array[int] = [0, 500, 1200, 2200, 3500, 5000]
const LOWER_BONUS_RENOWN: Array[int] = [0, 25, 60, 110, 175, 250]
const HUNTER_RISK_BONUS: Array[float] = [0.0, 0.0, 0.12, 0.25, 0.40, 0.55]
const ROMAN_GRADES: Array[String] = ["", "I", "II", "III", "IV", "V"]

## Active Trading Company StringName (empty when no Emissary flag is flying).
var active_company: StringName = &""
## Current Emissary Grade (0 = inactive, 1..5 = Grade I..V).
var grade: int = 0
## Cumulative Emissary progress points earned since raising the current flag.
var xp: float = 0.0


## Return the strict-ASCII short display name for a Trading Company ID.
static func company_short_name(company_id: StringName) -> String:
	match company_id:
		&"gilded_compass":
			return "Gilded Compass"
		&"sunken_archive":
			return "Sunken Archive"
		&"iron_tide":
			return "Iron Tide"
		_:
			return String(company_id).replace("_", " ").capitalize()


## Format a strict-ASCII Emissary HUD/menu badge string (e.g. "Gilded Compass Emissary III (1.67x)").
static func format_badge_text(company_id: StringName, p_grade: int, p_multiplier: float = -1.0) -> String:
	if company_id == &"" or p_grade <= 0:
		return ""
	var g := clampi(p_grade, 1, MAX_GRADE)
	var mult := p_multiplier if p_multiplier > 0.0 else GRADE_MULTIPLIERS[g]
	return "%s Emissary %s (%.2fx)" % [company_short_name(company_id), ROMAN_GRADES[g], mult]


## Return true while a valid Trading Company Emissary flag is currently raised.
func is_active() -> bool:
	return active_company != &"" and grade >= 1


## Raise an Emissary flag for `company_id`, starting at Grade I (0 XP, 1.00x).
func raise_flag(company_id: StringName) -> bool:
	if not VALID_COMPANIES.has(company_id):
		return false
	active_company = company_id
	grade = 1
	xp = 0.0
	flag_raised.emit(company_id)
	grade_changed.emit(company_id, 1, GRADE_MULTIPLIERS[1])
	return true


## Add Emissary progress points and advance cleanly through Grade I..V thresholds.
## Grants full points for matching or general deeds (`source_company == &""`), or
## `OFF_COMPANY_XP_FACTOR` (0.55x) for off-company piracy deeds. Returns current grade.
func add_progress(points: float, source_company: StringName = &"") -> int:
	if not is_active() or points <= 0.0:
		return grade
	var factor := 1.0 if (source_company == &"" or source_company == active_company) else OFF_COMPANY_XP_FACTOR
	xp += points * factor
	while grade < MAX_GRADE and xp >= GRADE_XP_THRESHOLDS[grade]:
		grade += 1
		grade_changed.emit(active_company, grade, GRADE_MULTIPLIERS[grade])
	return grade


## Return active payout multiplier (`1.0..2.5`) when active and matching `for_company` (or empty).
func get_multiplier(for_company: StringName = &"") -> float:
	if not is_active():
		return 1.0
	if for_company == &"" or for_company == active_company:
		return GRADE_MULTIPLIERS[clampi(grade, 0, MAX_GRADE)]
	return 1.0


## Return additional WorldDirector hunter risk contributed by the current Emissary Grade.
func get_hunter_risk_bonus() -> float:
	if not is_active():
		return 0.0
	return HUNTER_RISK_BONUS[clampi(grade, 0, MAX_GRADE)]


## Return Roman numeral label ("", "I", "II", "III", "IV", "V") for the current grade.
func get_grade_roman() -> String:
	if not is_active():
		return ""
	return ROMAN_GRADES[clampi(grade, 0, MAX_GRADE)]


## Return strict-ASCII badge text (e.g. "Gilded Compass Emissary III (1.67x)") or "" when inactive.
func get_badge_text() -> String:
	if not is_active():
		return ""
	return format_badge_text(active_company, grade, get_multiplier())


## Return gold cash-out bonus awarded if the active flag were lowered right now.
func get_lower_bonus_gold() -> int:
	if not is_active():
		return 0
	return LOWER_BONUS_GOLD[clampi(grade, 0, MAX_GRADE)]


## Return renown cash-out bonus awarded if the active flag were lowered right now.
func get_lower_bonus_renown() -> int:
	if not is_active():
		return 0
	return LOWER_BONUS_RENOWN[clampi(grade, 0, MAX_GRADE)]


## Voluntarily lower the Emissary flag at an outpost desk, crediting cash-out gold & renown.
func lower_flag(profile: Profile = null) -> Dictionary:
	if not is_active():
		return {
			"company_id": &"",
			"final_grade": 0,
			"bonus_gold": 0,
			"bonus_renown": 0,
		}
	var comp := active_company
	var final_grade := clampi(grade, 1, MAX_GRADE)
	var bonus_gold := LOWER_BONUS_GOLD[final_grade]
	var bonus_renown := LOWER_BONUS_RENOWN[final_grade]

	if profile != null:
		if bonus_gold > 0:
			profile.add_gold(bonus_gold)
			profile.bump_stat("gold_earned", bonus_gold)
		if bonus_renown > 0:
			profile.add_renown(String(comp), bonus_renown)

	active_company = &""
	grade = 0
	xp = 0.0
	flag_lowered.emit(comp, final_grade, bonus_gold, bonus_renown)
	return {
		"company_id": comp,
		"final_grade": final_grade,
		"bonus_gold": bonus_gold,
		"bonus_renown": bonus_renown,
	}


## Break the active Emissary flag when the ship sinks, returning salvageable trophy info and resetting.
func break_flag_on_sink() -> Dictionary:
	if not is_active():
		return {}
	var comp := active_company
	var lost_grade := clampi(grade, 1, MAX_GRADE)
	var comp_name := company_short_name(comp)
	var roman := ROMAN_GRADES[lost_grade]
	var broken := {
		"id": &"broken_emissary_flag",
		"name": "Broken Emissary Flag (%s %s)" % [comp_name, roman],
		"company_id": comp,
		"grade": lost_grade,
		"gold_value": 250 * lost_grade,
	}

	active_company = &""
	grade = 0
	xp = 0.0
	flag_broken.emit(comp, lost_grade)
	return broken


## Serialize active Emissary state for host-to-client replication or persistence.
func get_state() -> Dictionary:
	return {
		"active_company": String(active_company),
		"grade": grade,
		"xp": xp,
	}


## Restore serialized Emissary state cleanly.
func apply_state(state: Dictionary) -> void:
	var comp := StringName(String(state.get("active_company", "")))
	var g := clampi(int(state.get("grade", 0)), 0, MAX_GRADE)
	var x := maxf(0.0, float(state.get("xp", 0.0)))
	if comp == &"" or not VALID_COMPANIES.has(comp) or g <= 0:
		active_company = &""
		grade = 0
		xp = 0.0
	else:
		active_company = comp
		grade = g
		xp = x
