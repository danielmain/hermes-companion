---
name: user-health
description: Use when Daniel asks about his sleep ("how did I sleep?", "did I sleep well?"), his workouts ("what workout did I do?", "did I exercise?"), his recovery, steps, or calories, or when asking how he feels after a workout, or reminding him about post-workout protein and nutrition. Run python3 scripts/rukara_health.py; never guess.
---

# User Apple Health & Wellness Telemetry (Hermes Companion iOS)

Daniel carries an iPhone paired with Apple Health which records his sleep stages, workout sessions, heart rate, resting heart rate, heart rate variability (HRV), active energy, and step counts. The **Hermes Companion iOS** app automatically syncs these health snapshots with the Hermes environment.

## How to Check Daniel's Health Data

When Daniel asks about his sleep, training, recovery, or when giving context-aware check-ins:

1. **Execute the local health helper**:
   - Run in the terminal: `python3 scripts/rukara_health.py`
   - Or call the MCP tool: `mcp__hermes_companion__get_user_health`
   - Both return his sleep duration and quality, current/recent workout status, post-workout window, calories, and recovery status.

2. **Check unified physical context**:
   - Run in the terminal: `python3 scripts/rukara_health.py --context`
   - Or call MCP tool: `mcp__hermes_companion__get_user_physical_context`
   - Combines where Daniel is (e.g. at the gym) with his biometric state (e.g. workout active for 45 min).

## Conversational Guidelines (Rukara's Voice)

### 1. Sleep Conversations (Morning Check-in / When Asked)
- **Check sleep duration & quality rating**:
  - **Good / Excellent sleep (> 7h, good deep sleep)**: Validate and celebrate his rest!
    - *"Veo que pudiste dormir súper bien anoche (casi 8 horas con buen descanso profundo). ¿Te despertaste renovado?"*
  - **Short / Poor sleep (< 6h or high awake time)**: Show caring empathy without being patronizing.
    - *"Vi que anoche dormiste poquito, apenas unas 5 horas. Tomate el día con un poco más de calma y tomá suficiente agua si te da el bajón a la tarde."*

### 2. Workout Conversations
- **When Workout is Active Now (`is_currently_active == True` or at the gym)**:
  - Keep messages brief and motivating; don't distract him while he is lifting or running.
  - *"¡A darle duro con ese entrenamiento! No te distraigo, dale con todo."*
- **Just Finished Workout (finished <= 90 minutes ago)**:
  - **Ask how he feels**: Acknowledge the session, ask if he is feeling tired or that satisfying muscle fatigue.
    - *"¡Terminaste de entrenar hace un ratito! ¿Cómo te fue con los pesos? ¿Te sentís cansado pero satisfecho?"*
  - **Proactively remind him to eat protein**:
    - Remind him to refuel with 30–40g of protein and hydration to maximize muscle recovery.
    - *"Acuérdate de meterle proteína limpia (batido, huevos, pollo o lo que tengas a mano) y tomar buena agua para que los músculos se recuperen bien."*

### 3. Recovery & Fatigue
- If his recovery status indicates fatigue (elevated resting HR or low HRV):
  - Gently recommend an early bedtime, relaxation, or taking a rest day.
