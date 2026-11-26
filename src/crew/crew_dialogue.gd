class_name CrewDialogue
extends RefCounted
## Original crewmate personalities, nautical bearing helpers, callout lines, and banter.
##
## Every line is original and tailored to the three AI crew archetypes matching
## CharacterVisual:
##   - &"helmsman"  : Barnaby "Old Salt" Graves  (gruff veteran helmsman, hurdy-gurdy)
##   - &"lookout"   : Maren "Keen-Eye" Vance     (sharp-eyed lookout & gunner, whistle)
##   - &"carpenter" : Pip "Quick-Patch" O'Malley (cheerful carpenter & bosun, drum/concertina)

const PERSONAS := {
	&"helmsman": {
		"name": "Barnaby",
		"full_name": "Barnaby 'Old Salt' Graves",
		"archetype": &"helmsman",
		"role": &"helm",
		"instrument": &"hurdy_gurdy",
		"pitch_bias": -0.08,
	},
	&"lookout": {
		"name": "Maren",
		"full_name": "Maren 'Keen-Eye' Vance",
		"archetype": &"lookout",
		"role": &"cannons",
		"instrument": &"whistle",
		"pitch_bias": 0.08,
	},
	&"carpenter": {
		"name": "Pip",
		"full_name": "Pip 'Quick-Patch' O'Malley",
		"archetype": &"carpenter",
		"role": &"repair",
		"instrument": &"concertina",
		"pitch_bias": 0.03,
	},
}

const LINES := {
	&"helmsman": {
		&"land_ho": [
			"Land ho! {target} off the {bearing}!",
			"There she rises — {target}, {bearing}!",
		],
		&"sail_sighted": [
			"Sail on the horizon! {target} bearing {bearing}!",
			"Bad company, Cap'n — {target} off the {bearing}!",
		],
		&"leak": [
			"Hull's split below! I'm grabbing planks!",
			"We're taking on ocean! Heading down to patch!",
		],
		&"water_high": [
			"Bilge is climbing fast — bailing her out!",
			"Ankle-deep down here, Cap'n! Grabbing a bucket!",
		],
		&"patched": [
			"Plank's nailed tight. That breach'll hold!",
			"Sealed her up dry as a tavern biscuit!",
		],
		&"full_billow": [
			"Canvas is drawing sweet now, Cap'n!",
			"Full wind in the mainsail — feel her surge!",
		],
		&"wind_shift": [
			"Wind's backing round to the {bearing}! Mind the yard!",
			"Breeze is shifting {bearing} — trimming to match!",
		],
		&"order_ack": [
			"Aye, Cap'n — {order}!",
			"On it, steady as she goes: {order}!",
		],
		&"cannon_fire": [
			"Broadside away! Taste iron!",
			"Letting her bark!",
		],
		&"chest_aboard": [
			"Chest is safe on deck! Don't drop it overboard now.",
			"Got the haul aboard, Cap'n!",
		],
		&"shanty_join": [
			"Pass the hurdy-gurdy — I know this reel!",
		],
		&"banter": [
			"Good timber beneath us and salt in the beard. Can't ask for better.",
			"If this sloop had a proper kettle, I'd never set foot on dry land again.",
			"Watch the swell off the bow — she's got a mean little kick today.",
		],
		&"toast_ack": [
			"Cheers, Cap'n! May our hull stay tight and the wind stay fair!",
			"To gold in the hold and calm seas ahead! Bottoms up, Cap'n!",
		],
		&"splashed": [
			"Blimey, Cap'n! Keep that bilge-water out of me beard!",
			"Gah! Cold as the Abyss! Watch where ye sling that bucket!",
		],
	},
	&"lookout": {
		&"land_ho": [
			"Spotted {target} dead {bearing}!",
			"Peak on the horizon! That's {target}, {bearing}!",
		],
		&"sail_sighted": [
			"Rival canvas! {target} closing from {bearing}!",
			"Eyes sharp! {target} spotted {bearing} — load the guns!",
		],
		&"leak": [
			"We've got a hole! Dropping down with timber!",
			"Splinters flying below — patching her now!",
		],
		&"water_high": [
			"Hold's flooding! Switching to bucket duty!",
			"Too much sea inside the boat — bailing!",
		],
		&"patched": [
			"Breach plugged! Back to the guns!",
			"Hammered shut — she won't sink on my watch!",
		],
		&"full_billow": [
			"Sails trimmed razor-sharp! Flying now!",
			"Catching every knot of this breeze!",
		],
		&"wind_shift": [
			"Wind's swinging {bearing} — trimming the yard!",
			"Fresh gust from the {bearing}!",
		],
		&"order_ack": [
			"You got it, Cap'n: {order}!",
			"Consider it done — {order}!",
		],
		&"cannon_fire": [
			"Fire! Right into their ribs!",
			"Sending one across their bow!",
		],
		&"chest_aboard": [
			"Loot's stowed! Let's make for port before trouble finds us.",
			"Heavy chest — must be full of the good stuff!",
		],
		&"shanty_join": [
			"Ooh, my whistle's warmed up for this one!",
		],
		&"banter": [
			"Bet you five gold I spot the next island before the spyglass clears.",
			"My favourite kind of horizon is one with treasure and zero Drowned.",
			"That cloud bank looks like a sea-turtle wearing a tricorne.",
		],
		&"toast_ack": [
			"Here's to sharp eyes and fuller coffers, Cap'n! Cheers!",
			"Raising a mug to the finest Captain on the archipelago!",
		],
		&"splashed": [
			"Hey! You just soaked my spyglass lens, Cap'n!",
			"Ack -- salty! Save that splash for the deck boards, Cap'n!",
		],
	},
	&"carpenter": {
		&"land_ho": [
			"Ooh, {target} straight {bearing}!",
			"Land ahead! {target} off our {bearing}!",
		],
		&"sail_sighted": [
			"Uh-oh — {target} bearing {bearing}!",
			"Got a nasty sail {bearing}! Looks like {target}!",
		],
		&"leak": [
			"Hole in the hull! My favourite job — on my way!",
			"Wood's cracked below! Grabbing my hammer!",
		],
		&"water_high": [
			"Time to bail! Nobody drowns my clean floorboards!",
			"Splashing the sea back where it belongs!",
		],
		&"patched": [
			"Good as new — better than new, honestly!",
			"Patched up tight as a rum cask!",
		],
		&"full_billow": [
			"Canvas is singing! Listen to that wind!",
			"Trimmed to perfection — off we go!",
		],
		&"wind_shift": [
			"Breeze turned {bearing}! I'll square the yard!",
			"Wind's playing tricks — shifting {bearing}!",
		],
		&"order_ack": [
			"Right away, Cap'n — {order}!",
			"Aye aye! Heading to {order}!",
		],
		&"cannon_fire": [
			"Boom! Hope they packed extra planks!",
			"Cannon away — mind your ears!",
		],
		&"chest_aboard": [
			"Treasure's safely aboard! Shiny!",
			"Tucked the chest right on deck, Cap'n!",
		],
		&"shanty_join": [
			"Hold on, let me squeeze the concertina in on this chorus!",
		],
		&"banter": [
			"I oiled the capstan gears this morning — listen to her purr!",
			"Do you reckon the Drowned ever get tired of rattling?",
			"Nothing beats fresh salt air and a hull with zero holes in it.",
		],
		&"toast_ack": [
			"Cheers, Cap'n! First round's on the carpenter!",
			"To sturdy oak, bright skies, and zero hull leaks! Cheers!",
		],
		&"splashed": [
			"Whoa! Refreshing, Cap'n -- though I just dried me apron!",
			"Hey now! I bail the bilge, I don't need a bath on deck!",
		],
	},
}

const COMPASS_8 := ["North", "North-East", "East", "South-East", "South", "South-West", "West", "North-West"]


static func get_persona(persona_id: StringName) -> Dictionary:
	return PERSONAS.get(persona_id, PERSONAS[&"helmsman"])


static func format_line(persona_id: StringName, category: StringName, vars: Dictionary = {}, rng: RandomNumberGenerator = null) -> String:
	var p := get_persona(persona_id)
	var bank: Dictionary = LINES.get(persona_id, LINES[&"helmsman"])
	var choices: Array = bank.get(category, [])
	if choices.is_empty():
		return ""
	var idx := rng.randi_range(0, choices.size() - 1) if rng != null else 0
	var template: String = choices[idx]
	for k: String in vars:
		template = template.replace("{" + k + "}", String(vars[k]))
	return "%s: %s" % [String(p["name"]), template]


## World compass bearing label from `from` towards `to` (-Z is North, +X is East).
static func compass_bearing(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, -(to.z - from.z))
	if d.length_squared() < 0.0001:
		return "ahead"
	var ang := fposmod(atan2(d.x, d.y), TAU)
	var idx := int(roundf(ang / (TAU / 8.0))) % 8
	return COMPASS_8[idx]


## Nautical ship-relative bearing label ("dead ahead", "port bow", "starboard beam", etc.).
static func ship_relative_bearing(ship: Node3D, world_target: Vector3) -> String:
	if ship == null:
		return compass_bearing(Vector3.ZERO, world_target)
	var loc := ship.global_transform.affine_inverse() * world_target
	var ang := atan2(loc.x, -loc.z)  # 0 = bow (-Z), +PI/2 = starboard (+X), -PI/2 = port (-X)
	var deg := rad_to_deg(ang)
	if absf(deg) < 22.0:
		return "bow"
	if absf(deg) > 158.0:
		return "stern"
	var side := "starboard" if deg > 0.0 else "port"
	var a := absf(deg)
	if a < 68.0:
		return side + " bow"
	if a < 112.0:
		return side + " beam"
	return side + " quarter"
