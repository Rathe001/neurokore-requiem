# Narrative Bible

> **Status: Aspirational.** None of the content in this doc is implemented in the playtest. It exists as a worldbuilding reference for future work — the EF-723 setting, the cold open, the rep encounter structure, the Confrontation, the Sub-Level Zero categories. When in doubt about the world's *tone*, read this; when in doubt about what *currently runs*, read the code.

The starting-zone narrative (Earth Facility #723) is a four-level scripted progression that ends in a class choice. It is the project's narrative spine — every later zone is shaped by what happens here. **Leveling is disabled in the starting zone**; loot drops normally so the player can experiment with gear, but XP gain doesn't begin until they reach the first post-tutorial zone.

## Cold Open

The game opens cinematic-first. The player has no agency yet.

A figure — the player character — is held under bright examination lights. Two operators inspect it: a heavily augmented cyborg and a baseline human in corporate uniform. The cyborg runs a diagnostic. The human consults a tablet. They speak in clinical shorthand. They agree on something. The word *"defective"* lands in the conversation without ceremony.

**Character creation opens here.** The player picks origin (Analog / Cyborg), gender, avatar, name. The selection panel reads as the operators' interface — the player is, in narrative terms, *being assigned* their origin, not choosing it.

The cinematic resumes. The decision is made. One of the operators steps in with a device. The PC is zapped. The screen goes dark.

When the screen comes back, the PC is alone — Cyborgs wake on a procedure table in their wing, Analogs in a detention cell in theirs. The operator who declared them defective is dead in the room with them. The corpse is searchable and contains the player's first weapon.

> Design intent: the cold open establishes that the player is *property*, not a hero. Everything afterward is escape from a system that already wrote them off.

## Story Flow

The starting zone runs five levels, structured around the rep encounters and class choice:

| Level | Beat | Mechanics |
|---|---|---|
| **1** | First rep encounter — corridor escape, tough end-boss, rep intercepts | XP off, loot on |
| **2** | Second rep encounter — different boss flavor (e.g., damage-immune) | XP off, loot on |
| **3** | Third rep encounter — different boss flavor again (e.g., clone horde) | XP off, loot on |
| **4** | Confrontation room — all three reps converge, class choice | XP off, loot on |
| **5** | First post-tutorial zone — Sub-Level Zero begins | **XP on**, loot on |

**Boss intercept rules.** Each of levels 1–3 ends in a tough end-of-level boss. The boss is balanced to be *almost* unwinnable — the player's first taste of "you can't beat this on your own." When the boss reaches **50% HP** OR the boss reduces the player to 0 HP, the level's rep intercepts and one-shots it. The intervention is the rep's introduction. They explain who they are, hint at what they offer, and grant the player **tier 1 of their perk** as a working sample.

This means the player walks into the Confrontation having already *played* with three different power fantasies. The choice isn't theoretical.

**Boss flavor variation.** Each level's boss should feel different so the rep intercept doesn't read as a copy-paste. Working ideas: Level 1 a hard-hitting bruiser the player has to whittle down; Level 2 a damage-immune target the player can't possibly beat (rep removes the immunity by killing it); Level 3 a horde the player gets buried under (rep clears the room).

## Earth Facility #723

> **Design intent — the two-stage reveal.** The "EF-" prefix is doing deliberate misdirection. Early NPCs and terminal flavor name the facility by its full designation ("Earth Facility 723", "EF-723") in a way that primes the player to read "Earth" as *location* — i.e., "this is the 723rd facility on Earth, NeuroKore is a big corp." The truth is that "Earth" modifies *Facility*, not location: an *Earth-class* facility is itself a manufactured planet, nanogeoformed to Earthlike conditions, used end-to-end as slave-production infrastructure. The number 723 is this facility's serial — it implies *at least* 723 such planets exist, possibly far more. The reveal lands when the player learns the entire planet they've been on IS the facility, and that there are 722+ siblings out there full of cloned slaves. **Reveal timing is TBD** — could land at the Confrontation room, just inside Sub-Level Zero, or later. Whichever beat we pick, all earlier dialogue and terminal flavor must support the misdirection without contradicting it. Do not casually drop "planet" or "world" in early lore.

A vast corporate complex that served simultaneously as a cutting-edge augmentation research center and a high-security detention facility. The same corporation — **NeuroKore** — that pioneered augmentation technology also imprisoned those who resisted it.

The facility has been abandoned. Not destroyed, not decommissioned with care — simply left. A memo recovered from a terminal near the entrance:

> *"Re: EF-723 Operations Suspension*
>
> *Facility #723 has been flagged for decommission effective end of quarter. Current holdings represent ₩0.0000003% of Q3 portfolio. Operational costs no longer justify output. Asset recovery teams will not be dispatched. Regards, Resource Optimization Division."*

The people inside — patients, prisoners, staff, experiments — were not mentioned.

NeuroKore's scale is expressed in denominations that don't have common names. The number on this facility's designation is not a count of how many there are; it's a serial, and serials don't loop back.

### Layout

```
[ AUGMENTATION WING ]          [ DETENTION WING ]
  Cyborg starting zone           Analog starting zone
         |                              |
         |______________________________|
                       |
              [ CONVERGENCE POINT ]
               Lower maintenance
               corridors / escape
```

The two paths converge in the facility's lower maintenance infrastructure — utilitarian tunnels neither wing's inhabitants would typically have reason to enter. This is where Cyborg and Analog players meet for the first time before escaping together into Sub-Level Zero.

### The first NPC — exposition handoff

Shortly after escaping the starting room, the player encounters their first non-hostile presence. The encounter is class-specific in setting but identical in function: it delivers the core orientation dialogue.

- **Cyborg path:** a mostly disassembled cyborg laid out on a medical examination table. Lower body gone, internals exposed, still talking. Has been watching the wing fail through one functional optical sensor since the lockdown.
- **Analog path:** a prisoner whose cell door didn't open when the rest of the block went dark. Trapped behind a still-locked door. Gestures the player over to the intercom.

The dialogue beats:

1. *Where you are:* "You're in EF-723. NeuroKore facility. They decommissioned us last quarter."
2. *What happened to the player:* "Surgery went sideways when the shutdown hit. Whatever they were putting in your head — your control module, the loyalty conditioning, the leash — it didn't take. That's why you're walking around with your own thoughts."
3. *What the player is:* "You're a cloned slave. Made here, raised here, processed for assignment. The defect is what makes you free."

The NPC does not survive the conversation, or does not get to leave with the player — the medical-table cyborg fades during the exchange, the cell-locked prisoner can't be freed and sends the player on without them. This is the only character the player gets pure exposition from. Everything afterward is filtered through reps with agendas.

## The Representative System

Each starting zone is three rep-encounter levels (1–3) plus a Confrontation level (4). One specialized class rep per encounter level. The rep intervenes in a moment of genuine failure — at the level's end-of-zone boss — and the rescue is also when the player gets their first hands-on with the rep's power.

The pattern, per encounter:

1. **The level builds toward an end-boss the player can't reasonably beat** — body horror in the augmentation wing, organized resistance in detention. The fight feels real; the player is not aware they're being set up.
2. **At 50% boss HP, OR when the boss kills the player, the rep intercepts** and one-shots the boss. The player either gets to almost-win and watches the rep finish it, or gets to lose and watches the rep undo their loss. Either way the rep arrives as someone who didn't need to and chose to.
3. **The rep introduces themselves.** Short. They explain what they are in a few lines. They want the player to consider becoming one too.
4. **They grant tier 1 of their class perk** as a working sample. The skill tree opens for the rep's class only — the player can spend a granted point and *play* with the perk through the rest of the zone.

This pattern is repeated for the second and third reps with progressively more inventive boss flavor — see Story Flow above for the boss-variation idea.

By the time the Confrontation arrives, the player has been saved three times and tasted three different power fantasies. The choice is informed, not theoretical.

> Design intent — debt without coercion. Each rep's intervention is a gift, not a contract. The player owes each of them their life, but no rep frames the future relationship as repayment. The choice in level 4 has to *feel* free even though the path of least resistance is to follow whichever rep most recently saved you.

## Cyborg path: the Augmentation Wing

The Cyborg player wakes mid-procedure on an operating table. The corp abandoned them during an augmentation operation. Their last procedure is half-finished. The wing has been deteriorating ever since — failed experiments roam the halls, black market operators occupy the lower levels, and something is still running in the experimental labs at the core.

> The flavor passages below are the rep's *introduction beat* — in the new flow, this is the boss-intercept moment at the end of each level (per Representative System above). The setting framing is per-rep; the mechanic underneath it is uniform.

### Level 1 — The Ward

Half-finished patients shamble through the corridors — people abandoned mid-augmentation, some fused to equipment, some with procedures that went catastrophically wrong. The game's first introduction to body horror.

**Rep: The Forged.** A former corporate security enforcer given a prototype heavy chassis. When the corp pulled out, he stayed — maintaining brutal order over whatever the ward became. He finds the player pinned under a collapsed augmentation rig.

> *He tears the rig off you with one hand. He doesn't say much. He doesn't need to.*

### Level 2 — The Market

The black market that formed in the lower levels after the corp left. Desperate people, contraband augments, open firefights over territory.

**Rep: The Automaton.** A fixer who built a small empire through drone networks and scripted systems. Never personally in danger — always three cameras ahead, always a drone between herself and the problem. She clears an ambush the player was walking into before they even knew it was there.

> *You hear the shots before you round the corner. By the time you get there, four bodies and a drone hovering at eye level. It tilts slightly, like it's looking at you. Then it leaves.*

### Level 3 — The Core

The experimental labs. Sealed when the corp left. Something has been running in here since.

**Rep: The Polymath.** A volunteer research subject for cognitive augmentation beyond approved limits. Barely recognizable as a person. Knows things they couldn't possibly know. Stops the player in the corridor outside a room that looks completely empty.

> *"Don't go in there." He doesn't look at you when he says it. Three seconds later, the ceiling collapses into the room.*

## Analog path: the Detention Wing

The Analog player is an inmate in the facility's high-security detention block. The prison holds people who couldn't afford augmentation, refused it, or were flagged as threats to the corp's augmentation agenda. Many were destined for experimental procedures without consent.

The power goes out. The cells open. The blackout originates from the deepest solitary block — something the Enculted rep did, or something drawn to her, or both. It is not entirely clear.

> Same as the Cyborg path: the flavor passages below are the rep's introduction at the end-of-level boss intercept, per the Representative System pattern. The setting framing varies; the mechanic is uniform.

### Level 1 — The Cell Block

Chaos. Inmates in the corridors, augmented guards cracking down, the facility's security systems going dark in rolling waves.

**Rep: The Survivalist.** A fellow prisoner who has been preparing for exactly this. Has spent months converting contraband into weapons and mapping guard rotations. He finds the player cornered in a stairwell.

> *A door flies open. He throws you something you can't identify and says "figure it out" before disappearing around the corner. It works.*

### Level 2 — The Interior

The administrative and research sections between the cell block and the deep facility. More organized resistance from guards. Less chaos, more danger.

**Rep: The Count / Countess.** A political prisoner — incarcerated for refusing a mandatory augmentation order. Has maintained composure, routine, and an almost absurd dignity throughout their detention. The player walks into a corridor with a guard sniper covering the only exit.

> *A single shot from somewhere above and behind you. The sniper drops. She steps out of a maintenance shaft, straightens her collar, and gestures toward the exit.*

### Level 3 — The Deep Block

The oldest part of the facility. Solitary confinement for subjects deemed too dangerous or too unstable for general population. The lights here have been flickering for weeks. Guards stopped doing full patrols months ago.

**Rep: The Enculted.** In solitary. Has been here longer than the records show. When the player reaches the sealed door blocking the exit, it opens on its own. A guard standing ten feet away stares at the wall, unblinking, unreachable.

> *She steps out of her cell like she's been waiting. She doesn't explain the door. She doesn't explain the guard. She looks at you like she already knows what you're going to choose.*

## The Confrontation

Level 4 of the starting zone. All three reps the player has met converge in a single chamber — a sealed room with a locked gateway on the far side. The gateway is the exit from the tutorial. None of them can leave through it alone; the player's choice is what unlocks it.

The reps argue with each other first. Each is convinced their path is the obviously correct one, each dismissive of the others. The player watches three people who just saved their life disagree about everything except their belief that the player should follow them. The player can intervene in the conversation, ask each rep about themselves and the others, and direct the disagreement — this is the primary opportunity to understand each path before committing.

Eventually the reps turn to the player and present the ultimatum:

> *"Pick one of us. Or stay an origin and walk this alone. But the gate doesn't open until you decide."*

### The choice

When the player picks a class (or commits to remaining an origin), the gateway unlocks. **The unchosen reps leave through it.** No fight, no parting violence — they're not the player's enemies. They each made a different bargain with NeuroKore's wreckage and they're walking back into the world to keep making it. The chosen rep stays behind for one more conversation — short, characterful, the start of the player-companion relationship — and then the two of them follow.

The unchosen reps are gone for now. **They are not dead.** The world will reflect them living on parallel paths; later zones may surface one or both as ambient presences, news, allies of convenience, or eventual antagonists depending on how the player's chosen path drifts. Their lives continue without the player.

> Design note — this is a deliberate departure from the earlier bible draft, which had the Confrontation resolve as a 2v2 fight with the unchosen reps killed. The peaceful divergence makes the world feel populated by people with their own continuing stories, not props discarded after one use. Open question: what mechanical hook (if any) brings unchosen reps back into the player's path later? Reserved for whoever writes the second zone's narrative.

### The chosen rep, after

The chosen rep accompanies the player through the gateway and into Sub-Level Zero. They become the player's **representative companion** going forward:

- They appear at designated level-up points throughout the game — leveling is not done on the fly.
- They join certain boss encounters where it makes thematic sense.
- Their dialogue reacts to the player's talent progression and class transformation — they are the character most sensitive to how deep the player has gone.

## The Origin Class path

"Remain origin" is a fourth option in the ultimatum, and the reps know it. They don't approve, but they don't surprise the player with a fight either. When the player commits to staying origin, the three reps trade a look — disappointment, dismissal, or pity depending on the rep — and walk through the gateway. The room sits empty for a beat.

Then a fourth figure enters.

**The mystery rep** — an Analog for Cyborg players, a Cyborg for Analog players. They were never in the room before; the player has never seen them. They cross to the gateway and wait there for a moment before introducing themselves.

They are the rep of those who refused to sell themselves twice — first to NeuroKore for augmentation, then to one of NeuroKore's broken survivors for a cause. The only path that costs the player nothing and gives them nothing except themselves. They will fill the companion role going forward, same as any class rep.

The difference: the player didn't choose this. They refused to choose anything, and were given something anyway. The mystery rep knows this. They don't mention it — but they know.

**The mystery rep is the morally "good" path.** All six specialized classes represent a compromise. The origin class, under this companion, does not. This is reinforced by the origin class's breadth — they have access to all three specialist skill trees at shallow depth rather than one at full depth.

## Sub-Level Zero

The basement of Earth Facility #723. Below the augmentation wing. Below the detention block. Below everything. The first common zone after the Confrontation.

Sub-Level Zero was the facility's third operation — the one that doesn't appear on any public documentation. The prison population was the supply chain. Prisoners who refused augmentation, or whose augmentation responses were deemed anomalous, were transferred here. The bio weapons program used them.

When the facility was abandoned, Sub-Level Zero was not decommissioned. The experiments were not terminated. The door was locked from the outside, the power was cut, and the quarterly report moved on.

That was some time ago.

### Convergence

Sub-Level Zero is where the Cyborg and Analog paths meet for the first time. Both players escape downward from their respective wings and emerge into the same basement. They were in the same building for their entire starting zone without knowing it. Neither is expecting the other.

### The three categories

Three categories of enemy inhabit Sub-Level Zero, reflecting how long ago each experiment was abandoned:

**Abandoned** — functional weapons that were left running with no target and no handler. Still doing what they were designed to do. They have not changed. The horror is that they don't need to.

**Forgotten** — experiments the corp lost track of before the abandonment. Had time alone to change. The original design intent is no longer recognizable. Nobody knows what they are now, including them.

**Failed** — did not work as intended. Still alive. Still trying to complete an objective that their broken biology will never allow them to fulfill. The most unsettling category — not because they're dangerous, but because of what they're attempting.

### The Exit

Near the end of Sub-Level Zero, the player finds a functional elevator behind a lit doorway. The light is not neon. It is not special. It is just working light in a place where nothing works — and by the time the player reaches it, that is enough.

The elevator has power. The building has been dark for the entire playthrough. **Someone wanted this exit to stay open.**

The door leads out of Earth Facility #723 and into the world above.

> Open: who maintains the elevator? Why does it still have power? This implies an outside party with knowledge of and interest in the facility. Leaving it unresolved too long risks feeling like an oversight rather than a mystery.

## Rep alignments (character bible)

Each rep has a worldview shaped by who they are and what they sacrificed. They react when the player drifts from their alignment — not with judgment menus or system notifications, but through ambient dialogue, tone shifts, and occasional direct confrontation.

The morality plane that originally drove these reactions is on hold. The character bibles below stand on their own as worldbuilding regardless.

| Rep | Character notes |
|---|---|
| **Mystery Rep** | The "good" path. Reacts most strongly to drift toward selfish or corrupt decisions — the only rep whose worldview is not itself a compromise. |
| **Count / Countess** | Extreme arrogance and a superiority complex — *"I didn't need a machine to make me dangerous."* Their refusal of augmentation is not humility; it's contempt. Reacts to any loss of composure or signs of desperation. |
| **Survivalist** | Corrupted by trauma — watched everyone they knew get augmented, broken, or killed. Helps others because they've seen what happens when nobody does, but the cost has hollowed them out. Reacts to cold, self-serving decisions that mirror the people who destroyed everything they cared about. |
| **Automaton** | Binary logic has no room for selfishness — selfishness requires a self making a preference. The Automaton has dissolved their moral agency into scripts and systems. Not corrupted through malice, but through the removal of the self from the equation entirely. Reacts to emotional or personally motivated decisions as noise in the system. |
| **Enculted** | Sold their soul for power. The constant battle to prevent complete insanity is the price of that bargain — a cost they accepted knowingly. Reacts to selfless decisions as a waste of what they sacrificed everything to obtain. |
| **Polymath** | Made a conscious, deliberate decision to augment their intelligence for personal power. The "curiosity" framing is how they justify it. Corrupted through ambition dressed as scholarship. Reacts to decisions that suggest the player values others over their own advancement. |
| **Forged** | Power through total self-erasure. Reacts to any decision that suggests the player still values their humanity. |

The rep isn't a conscience system. They're a person with a worldview, and your choices are telling them who you really are.
