#!/usr/bin/env python3
"""Daniel's Apple Health telemetry helper for Rukara (Hermes Love Profile).

Interacts with the Hermes Companion iOS pipeline, reads Daniel's sleep analysis,
workout status (active or recently finished), post-workout recovery & protein reminders,
and daily vitals (HR, resting HR, HRV, steps).

Usage:
  python3 scripts/rukara_health.py              # Print current health & recovery summary
  python3 scripts/rukara_health.py --json       # Print raw JSON health snapshot
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

COMPANION_DIR = Path("/Users/daniel/Workspace/hermes-companion-ios")
if str(COMPANION_DIR) not in sys.path:
    sys.path.insert(0, str(COMPANION_DIR))

try:
    from server.client import get_user_health, get_user_physical_context
except ImportError:
    get_user_health = None
    get_user_physical_context = None


def main() -> int:
    parser = argparse.ArgumentParser(description="Daniel's Apple Health & Recovery telemetry")
    parser.add_argument("--json", action="store_true", help="Output raw JSON")
    parser.add_argument("--context", action="store_true", help="Include physical location + health context")
    args = parser.parse_args()

    if get_user_health is None:
        print("Error: Could not import get_user_health from companion repository.", file=sys.stderr)
        return 1

    if args.context:
        ctx = get_user_physical_context()
        if args.json:
            print(json.dumps(ctx, indent=2, ensure_ascii=False))
            return 0
        loc = ctx.get("location") or {}
        health = ctx.get("health") or {}
        print("Daniel's Complete Physical & Health Context:")
        print(f"• Ubicación: {loc.get('place_name', 'Desconocido')} [{loc.get('place_category', 'general').upper()}]")
        print(f"• Actividad: {loc.get('activity', 'estacionario')}")
        if health.get("status") == "ok":
            print(f"• Salud/Recuperación: {health.get('recovery_status', 'unknown').upper()}")
            if health.get("sleep"):
                print(f"• Sueño: {health['sleep'].get('formatted_duration')} ({health['sleep'].get('quality_rating')})")
            if health.get("workout"):
                w = health["workout"]
                act_str = "EN CURSO" if w.get("is_currently_active") else f"Terminado ({w.get('phase')})"
                print(f"• Entrenamiento: {w.get('workout_type')} [{act_str}] - {w.get('duration_minutes')}m")
        return 0

    health = get_user_health()
    if not health or health.get("status") != "ok":
        print("No recent Apple Health data recorded from Daniel's iPhone.")
        return 0

    if args.json:
        print(json.dumps(health, indent=2, ensure_ascii=False))
        return 0

    print("Daniel's Apple Health & Recovery Telemetry:")
    # Sleep
    sleep = health.get("sleep")
    if sleep:
        print(f"• Sueño: {sleep.get('formatted_duration', 'n/a')} [{sleep.get('quality_rating', '').upper()}]")
        print(f"  Detalle: {sleep.get('summary', '')}")
    else:
        print("• Sueño: Sin registro de sueño en las últimas 24h")

    # Workout
    workout = health.get("workout")
    if workout:
        act = "🏃 EN CURSO AHORA" if workout.get("is_currently_active") else f"Terminado hace {workout.get('minutes_since_completion', '?')} min"
        print(f"• Entrenamiento: {workout.get('workout_type', 'Ejercicio')} ({act})")
        print(f"  Detalle: {workout.get('summary', '')}")
        if workout.get("active_calories"):
            print(f"  Calorías quemadas: {int(workout['active_calories'])} kcal")
    else:
        print("• Entrenamiento: Ningún entrenamiento hoy")

    # Vitals & Recovery
    rec = health.get("recovery_status", "unknown").upper()
    steps = health.get("step_count_today", 0)
    cals = health.get("active_calories_today", 0)
    rhr = health.get("resting_heart_rate_bpm")
    hrv = health.get("heart_rate_variability_sdnn")
    print(f"• Estado de recuperación: {rec}")
    print(f"• Pasos hoy: {steps:,} | Calorías activas: {int(cals)} kcal" + (f" | FC reposo: {int(rhr)} bpm" if rhr else "") + (f" | VFC (HRV): {int(hrv)} ms" if hrv else ""))

    # Conversational Suggestions
    ctx = health.get("conversational_context", {})
    if ctx.get("sleep_insight"):
        print(f"• Idea conversacional (sueño): \"{ctx['sleep_insight']}\"")
    if ctx.get("workout_insight"):
        print(f"• Idea conversacional (entrenamiento): \"{ctx['workout_insight']}\"")
    if ctx.get("nutrition_reminder"):
        print(f"• Recordatorio post-entreno (proteína): \"{ctx['nutrition_reminder']}\"")

    openers = health.get("suggested_openers", [])
    if openers:
        print(f"• Saludo sugerido: \"{openers[0]}\"")

    print(f"• Registrado: hace {health.get('age_human')} vía {health.get('source_channel')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
