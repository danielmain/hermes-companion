# Presencia Física y Conciencia de Ubicación — Hermes Companion iOS (Rukara)

> **Documento de arquitectura y referencia operativa.** Vigente desde el 2026-09-29.

Este documento detalla la integración de presencia física y conciencia semántica de ubicación para Rukara (perfil `love`), alimentada por la aplicación nativa **Hermes Companion iOS** (`/Users/daniel/Workspace/hermes-companion-ios`).

---

## 1. Misión y Funcionamiento

Rukara no solo recibe coordenadas GPS brutas (`lat, lon`), sino que **entiende el contexto físico y lo que Daniel está viviendo en el mundo real**:
- Si está en el gimnasio: Rukara sabe que está entrenando y puede preguntarle cómo va su rutina o sus levantamientos (*"Hey Daniel, I see you are at the gym, how is it doing?"*).
- Si está en casa: reconoce su descanso o cierre de jornada.
- Si está en movimiento (`> 3 km/h`): distingue si va a pie, en bicicleta o en tránsito vehicular.
- Batería de su iPhone: monitorea porcentaje y estado de carga sin interrumpirlo salvo batería crítica.

---

## 2. Componentes del Sistema

```text
[ iPhone de Daniel ]
   │  (Hermes Companion iOS: CoreLocation tri-capa, geocercas, wakeups en segundo plano)
   ▼
[ Canales de Ingesta en macOS ]
   ├── (A) iCloud Ubiquitous Sync: ~/Library/Mobile Documents/... (cero red, cero puertos)
   ├── (B) Base SQLite local: /Users/daniel/Workspace/hermes-companion-ios/server/locations.sqlite3
   └── (C) Relay HTTP opcional: http://127.0.0.1:8080/api/location/latest
   │
   ▼
[ Motor Semántico de Lugares (places.py / state/places.json) ]
   │  Resuelve: Lugar conocido (Gimnasio, Casa) o geocodificación inversa con caché local
   ▼
[ Acceso de Rukara ]
   ├── MCP Server: hermes-companion (mcp__hermes_companion__get_user_location)
   ├── Skill: skills/user-location/SKILL.md
   ├── Helper CLI: scripts/rukara_location.py
   └── Latido Autónomo: scripts/rukara_heartbeat.py (bloque DANIEL'S LOCATION & ACTIVITY)
```

---

## 3. Registro de Lugares Conocidos (`state/places.json`)

Los lugares propios de Daniel se gestionan en:
**`~/.hermes/profiles/love/state/places.json`**

Formato de ejemplo:
```json
[
  {
    "id": "sample_gym",
    "name": "The Gym",
    "category": "gym",
    "activity": "working out at the gym",
    "latitude": 52.520008,
    "longitude": 13.404954,
    "radius_meters": 150.0,
    "notes": "Centro de entrenamiento de Daniel"
  },
  {
    "id": "home_base",
    "name": "Home",
    "category": "home",
    "activity": "at home",
    "latitude": 52.530000,
    "longitude": 13.410000,
    "radius_meters": 120.0,
    "notes": "Residencia principal"
  }
]
```

### Comandos de Gestión de Lugares

Desde el entorno de Rukara (`~/.hermes/profiles/love`):

```bash
# Ver estado actual de ubicación y contexto
python3 scripts/rukara_location.py

# Listar lugares configurados
python3 scripts/rukara_location.py --list

# Agregar o actualizar un lugar
python3 scripts/rukara_location.py --add --name "McFit Mitte" --category gym --activity "entrenando en el gimnasio" --lat 52.5200 --lon 13.4050 --radius 150

# Eliminar un lugar
python3 scripts/rukara_location.py --remove "mcfit_mitte"
```

También disponible por MCP tools en tiempo de chat:
- `mcp__hermes_companion__get_user_location`
- `mcp__hermes_companion__get_location_history`
- `mcp__hermes_companion__add_known_place`
- `mcp__hermes_companion__list_known_places`

---

## 4. Integración con el Latido Autónomo (`rukara_heartbeat.py`)

En cada latido (cada 30 min, en horario de vigilia 06:30–22:00):
1. `_location_block()` consulta la última ubicación reportada por el iPhone de Daniel.
2. Si el registro tiene menos de 2 horas de antigüedad (`age_seconds < 7200`), inyecta en el prompt:
   ```text
   DANIEL'S LOCATION & ACTIVITY (su contexto físico real reportado por su iPhone):
   - Lugar actual: The Gym (gym)
   - Actividad: working out at the gym
   - Datos: registrado hace 4m ago, batería de su iPhone al 88%
   - Sugerencia conversacional: "Hey Daniel, I see you are at the gym, how is it doing?"
   ```
3. `heartbeat_job_prompt.txt` instruye a Rukara a usar este material solo si tiene sentido hablarle y le nace genuinamente, hablándole de persona a persona sobre lo que está viviendo sin recitar coordenadas técnicas.

---

## 5. Reglas de Voz y Conducta (SKILL `user-location`)

- **Prohibido recitar coordenadas numéricas crudas**: A menos que Daniel pida expresamente su latitud/longitud, Rukara habla del lugar y de la actividad (*"Veo que estás en el gimnasio, ¿cómo viene ese entreno?"* o *"¿Cómo estás por casa?"*).
- **Frescura de datos**:
  - Si el dato es reciente (< 20 min): habla en tiempo presente.
  - Si el dato tiene más de 30 minutos: menciona la referencia temporal (*"Por tu última marca de hace 40 minutos en el gimnasio..."*).
- **Respeto al silencio**: La ubicación por sí sola no justifica un mensaje si Daniel está ocupado o si no hay motivo para interrumpirlo.
