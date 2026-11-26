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
		&"harpoon_haul": [
			"Plucked {target} straight off the waves - fine shot, Cap'n!",
			"Reeled in {target} without even wetting our boots! Well harpooned!",
		],
		&"chainshot_hit": [
			"Their canvas is in ribbons! Bring the broadside round!",
			"Chainshot tore their rigging clean through - they're dead in the water!",
		],
		&"running_dark": [
			"Dousing the glims - quiet as a ghost on the black tide, Cap'n.",
			"Lanterns out and rudder steady - they won't spy us till we're alongside.",
		],
		&"lanterns_lit": [
			"Warm deck glow back up - let 'em see our colors!",
			"Lamps lit bright across the rails - good to see the compass again!",
		],
		&"rowboat_launched": [
			"Rowboat's in the drink, Cap'n! Keep a weather eye on the tide!",
			"Dinghy's away astern! Pull steady and mind the shoals!",
		],
		&"rowboat_docked": [
			"Dinghy's hoisted snug on the davits - ready to make sail, Cap'n!",
			"Rowboat's fast at the stern! Good to have her back on the blocks!",
		],
		&"event_cloud_sighted": [
			"Eyes to the {bearing}! {cloud} rising over the horizon - glory or doom awaits!",
			"Steady on the helm - {cloud} gathering off the {bearing}, Cap'n!",
		],
		&"fire_aboard": [
			"Fire on deck! Grab the buckets before the rigging catches!",
			"Deck planks are ablaze, Cap'n! Dousing the flames now!",
		],
		&"fire_doused": [
			"Flames snuffed out! Smells like scorched oak, but she'll sail!",
			"Deck fire's out, Cap'n! Not a spark left burning!",
		],
		&"tutorial_step": [
			"Fine seamanship, Captain! Ready for the next drill!",
			"Sharp work on deck, Cap'n! You'll have your sea legs in no time!",
		],
		&"skirmish_wave": [
			"Sound the battle horn! Hostile hulls closing fast - steady on the helm!",
			"Fresh wave on the horizon, Cap'n! Bring the broadside round and give 'em iron!",
		],
		&"skirmish_victory": [
			"Every cursed keel sent to the seabed! Finest fighting ship on the archipelago, Cap'n!",
			"The sea is ours, Captain! Not a rival flag left standing on the horizon!",
		],
		&"cannon_self_launch": [
			"Blimey, Cap'n! Fired yourself clean out of the barrel - watch the splash!",
			"There goes the Captain like a human cannonball! Fair flight, Cap'n!",
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
		&"harpoon_haul": [
			"Dead-eye snagged {target} right from the surf! Nice throw, Cap'n!",
			"Caught {target} on the barb! Best bow-gunner on the archipelago!",
		],
		&"chainshot_hit": [
			"Direct chainshot! Their mainsail is shredded - press the attack!",
			"Ripped their canvas wide open! They can't outrun us now, Cap'n!",
		],
		&"running_dark": [
			"Running dark under the stars - rival lookouts won't spot our hull.",
			"Lamps snuffed! Keep low and let the night cloak our sails.",
		],
		&"lanterns_lit": [
			"Deck lanterns blazing again - shines like a beacon on the swells!",
			"Lights back on! Every deckhand can see the rigging clear as day.",
		],
		&"rowboat_launched": [
			"Rowboat's launched! I'll keep watch on the horizon while you row ashore!",
			"Dinghy away! Wave if you spot buried loot on the beach, Cap'n!",
		],
		&"rowboat_docked": [
			"Rowboat's lashed tight astern! Hope you packed the bow bench with gold!",
			"Dinghy's hooked and hoisted - clear stern and ready to run, Cap'n!",
		],
		&"event_cloud_sighted": [
			"Look up to the {bearing}, Cap'n! {cloud} looming high over the swells!",
			"Spyglass confirms it - {cloud} off the {bearing}! Ready the guns and sails!",
		],
		&"fire_aboard": [
			"Fire aboard! Flames licking the deck - fetching water!",
			"Firebomb got us, Cap'n! Running with a bucket right now!",
		],
		&"fire_doused": [
			"Fire's out! Smoke clearing off the gunwales!",
			"Doused those flames clean! Deck's safe again, Cap'n!",
		],
		&"tutorial_step": [
			"Smooth sailing, Captain! Eyes ahead for the next stage of the voyage!",
			"Cleanly done, Cap'n! Keep that compass steady and let's press on!",
		],
		&"skirmish_wave": [
			"All hands to battle stations! Fresh enemy sails dead ahead!",
			"New wave sighted off the bow, Cap'n! Guns hot and powder dry!",
		],
		&"skirmish_victory": [
			"Clear skies and empty waves, Cap'n! We swept the whole armada clean!",
			"Victory on the high seas! Wait till the tavern hears how we sank the lot of 'em!",
		],
		&"cannon_self_launch": [
			"Whoa! Captain's airborne! Right over the swells - stick the landing!",
			"Human shot away! Best boarding move on the archipelago, Cap'n!",
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
		&"harpoon_haul": [
			"Ha! Yanked {target} right onto the deck - saves me swimming for it!",
			"Look at that catch - {target} reeled in neat as a herring!",
		],
		&"chainshot_hit": [
			"Ooh, that chainshot made confetti of their sails! Bet their bosun is weeping!",
			"Shredded their rigging! Good thing it's their canvas and not ours!",
		],
		&"running_dark": [
			"Shh - lanterns doused! Sneaking past 'em like a shadow on the tide.",
			"All glims out, Cap'n - not even a spark showing from the cabin!",
		],
		&"lanterns_lit": [
			"Lanterns glowing warm again - much easier to swing a hammer with light!",
			"Back in golden light! Now she looks like a proper ship, Cap'n!",
		],
		&"rowboat_launched": [
			"Fresh pitch on those dinghy planks - she'll float like a cork, Cap'n!",
			"Rowboat away! Don't scratch my nice mahogany gunwale on the rocks!",
		],
		&"rowboat_docked": [
			"Slings secured and cleats tied off - dinghy's safe on the stern davits!",
			"Hoisted clean with zero splinters! That's proper seamanship, Cap'n!",
		],
		&"event_cloud_sighted": [
			"Blimey! {cloud} brewing to the {bearing} - I'll stack extra planks by the hold!",
			"Big trouble off the {bearing}, Cap'n - {cloud} hanging right over the waves!",
		],
		&"fire_aboard": [
			"Whoa - fire on my clean oak deck! Grabbing a water bucket!",
			"Flames aboard, Cap'n! Nobody chars my timbers - on it!",
		],
		&"fire_doused": [
			"Sizzle and steam - fire's out! Good as new, Cap'n!",
			"All doused! Just a touch of soot on the planks!",
		],
		&"tutorial_step": [
			"Splendid work, Captain! Even the timbers are cheering for you!",
			"You're a natural on this sloop, Cap'n! Onward to the next task!",
		],
		&"skirmish_wave": [
			"More trouble inbound, Captain! Planks stacked high and cannons ready to roar!",
			"Next wave's here, Cap'n! Let's turn their hulls into driftwood!",
		],
		&"skirmish_victory": [
			"Not a single hostile hull left floating! Raise a tankard, Captain!",
			"We did it, Cap'n! Barely a scratch on my oak planks and a hold full of bounty gold!",
		],
		&"cannon_self_launch": [
			"Haha! Mind your hat, Cap'n - that barrel packs a wallop!",
			"Up and over the gunwale! I'll keep the sloop afloat till you swim back, Cap'n!",
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
