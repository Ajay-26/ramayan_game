# Ramayan — Single-Level Prototype Design Doc

*Status: locked v1 (approved 2026-11-21). Open questions at the bottom don't block Milestone 1.*

## Pitch
A short, free, browser-playable action game: **Prince Rama** fights through a cursed forest at night to protect Sage Vishwamitra's yagna, ending in a battle with the demoness **Tataka**. It uses a fixed cinematic camera and combo combat in the spirit of early 2000s action games, with an anime look inspired by traditional Indian attire.

Goal: a 15–25 minute level to share with friends and see how people react.

## Pillars
1. **Rama is an archer first.** The bow is the hero weapon. Blades and chakra support it.
2. **Divine light in a dark world.** Rama glows gold and blue against a violet night lit by orange fire.
3. **Small and finished beats big and broken.** One polished level, no half-features.
4. **Respectful.** Mythic tone, no gore. Rakshasas burst into ash and embers.

## Tech
| Item | Choice |
|---|---|
| Engine | Godot 4.7.2 |
| Renderer | **Compatibility** (switch from Forward+). Needed for web export |
| Physics | Jolt (already set) |
| Primary build | **Web build on itch.io**, restricted page shared by link |
| Secondary build | Windows `.zip` on the same itch page |
| Input | Keyboard + mouse, and gamepad. Desktop browsers only, no mobile |
| Perf target | 60 fps in a browser on Intel Iris Xe-class laptops |
| Download size | Aim for under 150 MB |

## Camera
Fixed cinematic camera. Each area has **camera zones** (rails or fixed points) that track Rama and blend between shots. The camera pulls wide for the arena and boss, and tight for stealth. The player never controls the camera directly.

Aiming with a fixed camera: **soft lock-on**. The bow and chakra target the best enemy in the direction Rama is facing, and a right stick flick or mouse movement switches targets.

## Controls (draft)
| Action | Keyboard/Mouse | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Light attack (blades) | LMB | X / Square |
| Heavy attack (blades) | RMB | Y / Triangle |
| Bow (tap = quick shot, hold = charged) | E | R2 / RT |
| Throw chakra (returns automatically) | Q | R1 / RB |
| Dodge roll (i-frames) | Shift | B / Circle |
| Jump | Space | A / Cross |
| Crouch / sneak | C | L3 |
| Stealth takedown / interact | F | (contextual) Square |
| Divine astra (when meter is full) | R | L1 + R1 |
| Switch target | Mouse / Tab | Right stick flick |

## Rama's Arsenal
| Weapon | Role | Moves |
|---|---|---|
| **Twin short blades** | Fast melee + stealth | 4-hit light combo, 2-hit heavy, launcher, air combo, silent takedown from behind |
| **Bow** | Ranged precision | Quick shot, charged piercing shot, **fire arrows** (shoot through torches) |
| **Chakra** | Crowd control + puzzles | Thrown in an arc, hits everything on its path out and back, staggers enemies, breaks shields from behind, hits switches and bells |
| **Divine astra** | Emergency special | Meter fills from combat. Screen-clearing divine blast, usable about once per big fight |

No blocking. Defense is dodge and spacing, which keeps scope down.

## Enemies
| Enemy | Behavior | Counter |
|---|---|---|
| **Rakshasa grunt** | Club or sword, groups of 3–6 | Blades |
| **Rakshasa archer** | Fires from ledges | Bow |
| **Shielded brute** | Big frontal shield, slow slams | Chakra from behind, or a charged arrow to stagger |
| **Tataka (boss)** | Giant demoness, 3 phases | Everything |

All enemies die in an **ash and ember burst**.

## Level Flow: "Siddhashrama at Night"
| # | Beat | Teaches | Est. time |
|---|---|---|---|
| 0 | **Intro:** painted story cards plus text. Vishwamitra asks Rama to protect his yagna | Story | 1 min |
| 1 | **Forest at dusk:** movement, then sneak past and take out 3–5 sentries | Movement, stealth takedowns | 3 min |
| 2 | **Rakshasa camp:** stealth breaks, first real fight | Blade combos, dodge | 3 min |
| 3 | **Ravine:** archers on ledges, explosive pots, fire arrows from torches | Bow | 4 min |
| 4 | **Ruined shrine:** Vishwamitra grants the chakra. Bell/switch puzzle, then a brute fight | Chakra | 4 min |
| 5 | **Yagna defense:** night falls. Waves of mixed enemies while the sacred fire burns. The altar has its own health bar | Everything, astra | 4 min |
| 6 | **Boss: Tataka.** Five stages, ground and sky (see below) | Mastery | 8–12 min |
| 7 | **Ending card:** "To be continued…" plus a feedback link | — | — |

### Tataka, Rider of the Storm (boss)
Tataka attacks from the clouds. A long, Souls-style fight in **five stages**, each a fifth of her health bar (marked on the bar). Burst damage can't skip a stage: her health stops at the line and she changes, invulnerable, with a banner and a line from Vishwamitra. No checkpoints mid-fight by default (`stage_checkpoints` on the Boss node turns them on); healing herbs sprout at the start of stages 3 and 5.

| Stage | Name | What she does | How Rama answers |
|---|---|---|---|
| 1 | The Demoness | Ground: sweeps, 2-hit strings, slams, a stomp if Rama hides behind her, boulder throws, leaps across the arena onto a marked spot | Dodge the telegraph, punish the recovery, stagger her with damage |
| 2 | Storm-Rider | Takes to the sky between ground bouts. Her shadow hunts Rama, then stops, then she dives; low swoops across a marked lane; burning stones from the clouds; demon fire orbs | Bow: enough arrows knock her out of the sky; she crashes and takes extra damage |
| 3 | The Brood | Ground, quicker: 3-hit strings, delayed slams, charges (hit a wall and she's dazed), summons rakshasas | Crowd control, chakra, astra |
| 4 | Maya | Hides in a low storm-cloud deck, unseen and untouchable. Lightning reveals her for a moment; she shows herself to dive and swoop | Watch the sky, shoot during reveals and after attacks |
| 5 | Fury | Enraged: everything faster, demon fire on the ground, short flights for a dive | Everything. At zero she kneels: **takedown** for the final blow |

Every attack has a wind-up and a ground telegraph (circle, lane, or a hunting shadow). The storm builds through the fight: cloud deck, rain, darkness, lightning.

Support systems: health bar, astra meter, glowing healing herbs as pickups, a checkpoint at each beat.

## Art Direction
- **Look:** grim, cinematic mid-2000s action game: dark, high-contrast scenes with deep shadows, heavy soft bloom on fire and divine light, thick colored fog, and a stormy night sky. A full-screen grade (`shaders/cinematic_grade.gdshader`) crushes the blacks, desaturates the midtones, and splits the color: cold slate-teal shadows, warm bronze highlights. Characters get a bright rim light so they read against the dark. We make our own designs and don't copy any existing game's characters or art.
- **Outfits:** inspired by traditional Indian royal and ascetic attire.
  - Rama: blue skin, golden mukut and ornaments, yellow/saffron dhoti, angavastram, bow across the back
  - Vishwamitra: ascetic, white beard, saffron robes, rudraksha beads
  - Rakshasas: dark rough skin, horns, tusks, crude bone and iron armor, glowing eyes
  - Tataka: towering, wild hair, ash-grey skin, fire-orange eyes, jewelry of bones
- **Palette:** cold moonlit slate and storm grey, hot orange firelight, Rama in gold and blue.
- **Grit:** ash and embers drifting in the air, rain and lightning in the storm, smoke, scorched ground, film grain, vignette.

## Asset Pipeline
| Asset | Source | Who |
|---|---|---|
| Characters | AI 3D generator (Meshy / Tripo / Hunyuan3D) → simplified textures | **You** generate (needs your accounts). I give you exact prompts |
| Rigging + animations | **Mixamo** auto-rig + free animation library | **You** download (needs Adobe login). I give you a list |
| Environment | CC0 packs (Quaternius, Kenney, Poly Haven), plus simple temple and ruin pieces built in-engine | Me |
| VFX, shaders, lighting, UI | Built in Godot | Me |
| SFX | CC0 (Freesound CC0, Sonniss GDC bundles) | Me (sourcing list), you download if needed |
| Music | TBD (see open questions) | — |
| All code, levels, gameplay, builds | — | Me |

**Greybox first:** capsules and blocks until combat feels good, then swap in art.

## Build Order (Milestones)
1. **Combat feel (greybox):** capsule Rama, camera zones, movement, dodge, blade combos, grunt AI, hit-stop, screen shake, ash death. **Test the web export on day one.**
2. **Full arsenal:** bow + lock-on, chakra, stealth takedowns, astra. Archer and brute enemies.
3. **Level blockout:** all 8 beats playable in greybox, with checkpoints and yagna waves.
4. **Tataka boss.**
5. **Art pass:** characters, toon shader, environments, lighting, VFX, audio.
6. **Polish and ship:** title menu, pause and settings, intro/outro cards, feedback link, itch.io upload.

After each milestone you play it in the editor (F5) and give feedback before I move on.

## Explicitly Out of Scope
Open world, skill trees, upgrades, voice acting, Lakshmana as a playable or AI companion, multiplayer, mobile, save files (checkpoints only), full stealth system (alert states, hiding in bushes, etc.).

## Open Questions
1. **Canon order.** In Valmiki's telling, Rama slays Tataka on the journey *before* reaching the ashram, then defends the yagna against Subahu and Maricha. Options:
   - **(a)** Keep the plan above (creative license: Tataka attacks the yagna).
   - **(b)** Reframe the level as **"Tataka Vana"**: the journey through her forest ends with Tataka, and the ending card teases the yagna defense as the next level. More faithful, same scope. Beat 5 becomes a defense of Vishwamitra's camp.
2. **Lakshmana:** cutscene-only (recommended), or absent?
3. **Title:** working title "Ramayan". Final name?
4. **Music:** CC-licensed tracks, AI-generated, or a musician friend?
