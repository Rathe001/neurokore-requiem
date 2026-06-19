# Steam patch notes — v0.5.0 (BuildID 23824650)

Paste-ready for the Steamworks "Set Build Live" form. The description body is
Steam-flavored BBCode. Copy the title and body sections below directly.

---

## Patch notes title

v0.5.0 — The Overhaul Update

---

## Patch notes description (Steam BBCode)

[h2]A big one. The whole game got a visual and performance overhaul.[/h2]
This update rebuilds the characters, weapons, animations, and gore from the ground up, and lands a major performance pass on top. Thanks for testing — here's what changed.

[h2]✨ New Look[/h2]
[list]
[*][b]All-new characters and weapons.[/b] Players, enemies, and every weapon were rebuilt on custom low-poly models with proper PBR textures — roughly 16× fewer triangles than before, which drives most of this build's smoother framerate. Enemies now split into distinct grunt and boss bodies.
[*][b]Weapons are visible in your hands.[/b] Every equipped weapon now shows up on the character — on you and on enemies — and shots, beams, and muzzle flashes come out of the actual barrel.
[*][b]Full animation overhaul.[/b] Per-weapon stances (pistol / rifle / melee), aimed firing poses that sync to your fire rate, real strafing, and melee swings that land their hit on the true impact frame. Non-explosive kills now play proper death animations instead of always ragdolling.
[*][b]Shell casings and dropped weapons.[/b] Guns eject brass as they fire, and enemies drop their weapon as a physics object when they die.
[/list]

[h2]🩸 Living Blood[/h2]
[list]
[*][b]Blood is now a persistent ground effect.[/b] Kills leave growing pools that settle under the corpse and merge when they touch, walls take splatter with gravity drips, and you'll track bloody footprints out of a pool.
[*][b]Blood is slippery.[/b] Standing in a pool applies a traction debuff. Boots now carry a Traction stat that mitigates slick surfaces.
[/list]

[h2]⚔️ Combat & Feel[/h2]
[list]
[*][b]New camera[/b] — a tighter, closer view framed on your character.
[*][b]Melee rebalanced[/b] — swing speeds, damage, and impact timing retuned so melee hits land right and read bigger.
[*][b]Explosions fixed[/b] — RPG, grenade, and strike blasts now match their real damage radius and no longer reach through walls.
[*][b]Impact craters[/b] scorch the floor from heavy slams and explosions.
[*][b]Neon highlights[/b] on switches, elevators, and pickups so it's clear what you can interact with.
[/list]

[h2]🚀 Performance[/h2]
[list]
[*]Levels now stream in instead of freezing on entry.
[*]Eliminated hitches at room transitions, on level-up, and — notably — the per-shot freeze when firing the laser pistol.
[*]Distant and idle enemies throttle their processing; ragdolls are queued so multi-kills don't spike.
[*]New Display settings: VSync, FPS cap, and a Global Illumination quality toggle.
[/list]

[h2]🛠️ Notable Fixes[/h2]
[list]
[*]You can no longer walk inside the switch console, and elevators are reachable again.
[*]Mission tracker no longer spams duplicate objective lines.
[*]Blood no longer pre-stains walls at level start; the slip debuff only applies while you're actually in a pool.
[*]Decals no longer hang off platform edges over empty space.
[*]Fixed twisted legs while aiming and floating feet while strafing.
[*]Co-op: remote players now correctly take damage.
[/list]

[i]Keep the bug reports coming — especially anything you hit across multiple levels in a row.[/i]
