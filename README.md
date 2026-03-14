# 🧠 Procedural Content Generation & Feature Additions to a prebuilt PacMan Game

This project now includes a robust suite of **Procedural Content Generation (PCG)** systems, dynamic gameplay mechanics, and new in-game features implemented throughout development.  
Below is a complete summary of all functionality added across enemies, pellets, player abilities, and game systems.

---

# ⚙️ 1. Enemy PCG System  
A dedicated **PCG Manager** and **Enemy PCG Factory** were added to procedurally configure enemies every run.

### **Procedurally Controlled Enemy Parameters**
Each enemy receives randomized attributes depending on selected difficulty (Easy / Medium / Hard):

- **Base speed** (with scatter, chase, frightened multipliers)
- **Prediction offset** (how far ahead enemies target the player)
- **Scatter time**
- **Chase time**
- **Frightened duration**
- **Direction change cooldown**
- **Spawn delay**
- **Frightened speed multiplier**

These parameters are generated every game start, producing unique and dynamic enemy behavior for each run.

---

# ⚔️ 2. Assassin Teleportation PCG System  
The Assassin enemy was extended with a **new advanced teleportation system**, fully driven by PCG parameters.

### **Teleport Behavior Features**
- Teleport occurs periodically depending on a procedurally generated cooldown.
- A warning flash (golden tint) appears before teleporting.
- Teleportation respects min/max tile radius constraints.
- Assassin freezes during teleport charge-up.
- Teleportation word/voice-line randomly selected for flavor:  
  *“Ambush!”, “Behind You!”, “Sneak!”, etc.*

### **Teleportation Styles (PCG-Selectable)**
Multiple teleport pattern modes were implemented:

- **AMBUSH_BEHIND** (behind player)
- **FLANK** (side attack)
- **PREDICTIVE** (in front of predicted player path)
- **RANDOM_NEAR** (random tile within radius)

### **Weighted Style Randomization**
Each teleport event can roll a different style using PCG-defined probability weights.

### **Teleport Sound Effect**
A custom teleport sound file plays on successful teleport.

*(Later simplified to always use AMBUSH_BEHIND at your request.)*

---

# 🟡 3. Rare Golden Pellets System  
Normal pellets were expanded into a new **Rare Pellet System**, including:

### **PCG Rare Pellet Placement**
Depending on difficulty:

- **Easy:** 10 rare pellets  
- **Medium:** 5 rare pellets  
- **Hard:** 2 rare pellets  

Pellets are selected randomly each run and recolored **gold**.

### **Rare Pellet Metadata**
Each rare pellet receives:

```gdscript
pellet.set_meta("is_rare_pellet", true)
```

Used for identifying rare pellet pickups.

### **Gold Color**
Rare pellets are visually distinguished using:

```gdscript
pellet.modulate = Color(1.0, 0.84, 0.0)
```

---

# ⚡ 4. Rare Pellet Buff System  
Collecting a rare pellet grants **temporary buffs**, with duration scaling by difficulty.

### **Buff Duration**
- **Easy:** 15s  
- **Medium:** 10s  
- **Hard:** 5s  

### **Buff Effects**
- **Player speed boost** (moderated so gameplay remains controllable)
- **Ghosts slow down during buff**
- **Bonus score depending on difficulty:**
  - Easy: +200
  - Medium: +400
  - Hard: +1000

### **Global Buff Signals**
Added to `global.gd`:

- `rare_pellet_buff_started(multiplier, duration)`
- `rare_pellet_buff_ended()`
- `rare_pellet_bonus_display_requested(value)`

### **Buff Handling in Player**
- Player stores base speed.
- Applies temporary speed multiplier.
- Restores speed when buff ends.

---

# 👻 5. Ghost Slowdown During Rare Buff  
All enemies respond to the rare pellet buff:

- Their movement speeds are lowered proportionally.
- Changes revert cleanly on buff expiration.

Enemy movement logic was updated to support buffed and unbuffed states.

---

# 🔢 6. Golden Score Popup System  
When picking a rare pellet:

- A **golden floating score number** appears above the player.
- Uses the shared `NumbersDisplayer` scene.
- Rendered in gold (`Color(1, 0.84, 0)`).

Triggered by:

```gdscript
Global.rare_pellet_bonus_display_requested.emit(value)
```

Handled inside `player.gd`.

---

# 🧩 7. Fixes & Refactors Implemented  
The PCG systems introduced several necessary internal improvements:

### **Fixes & Stabilization**
- Repaired missing references (timers, SharedEnemyAI, nodes, signals, wrong paths).
- Fixed indentation inconsistencies (tabs vs spaces).
- Corrected Elroy Mode speeding crash.
- Ensured `base_speed` and buff speed do not cause uncontrollable movement.
- Updated Pickable and Player systems with defensive checks.
- Repaired teleport timer initialization issues.
- Ensured safe pellet recoloring (1 child only).

### **Safety & Architecture Improvements**
- Added null-checks and method-checks everywhere.
- Cleaned up legacy signals and integration points.
- Made PCG application idempotent (runs only once).
- Guaranteed consistent run-to-run behaviors via seeded RNG.

---

# 🎮 8. Enhanced Gameplay & Visual Feedback  
Additional polishing and functional upgrades:

- Teleportation warning flash & teleport sound.
- Golden pellet visual clarity.
- Floating bonus score display.
- Balanced and playable rare pellet speed boosts.
- Improved teleport animation behavior.
- Clean directional & movement transitions across all states.

---

# 🏗️ 9. Codebase Architecture Upgrades  
To support new gameplay systems:

### **PCGManager**
Central controller responsible for:
- Enemy procedural generation  
- Rare pellet selection  
- Golden pellet recoloring  

### **Modular EnemyAI Inheritance**
All advanced teleport logic lives inside `EnemyAIAssassin`, cleanly subclassed.

### **Signal-Oriented Architecture**
Global emits buff and score events to avoid spaghetti references and keep systems decoupled.

---

# 📌 Summary  
The project now includes:

✔ Fully dynamic enemy behavior through PCG  
✔ Rare pellet selection & gold recoloring  
✔ Rare pellet buffs (speed boost, ghost slowdown, scoring)  
✔ Golden popup score visuals  
✔ Assassin teleport PCG system  
✔ Weighted teleport styles  
✔ Gameplay polish (sounds, animations, visual effects)  
✔ Major bug fixes & architectural hardening  
✔ Clean signals-based communication  
✔ Improved difficulty scaling & replayability  

These systems greatly enhance gameplay variety, unpredictability, and long-term replay value while keeping behavior fair and controllable.
