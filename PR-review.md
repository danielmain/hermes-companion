Two things in companion.py reach the model as facts but aren't measured.
1. still_there is the literal True

:263 puts "still_there": True in resolve_location's return dict
unconditionally, and :337 re-prints it as a constant still_there: yes.
SKILL.md's Quick Reference lists still_there under "Where are they? →
Fields to trust".

Driving the real function:
input 	still_there 	place_name 	is_moving_now
walking 	True 	Home 	True
automotive 	True 	In Transit 	True
unlisted coord 	True 	Unlisted place 	False
stationary 3h at Home 	True 	Home 	False

The driving row is the awkward one: place_name already says In Transit,
and the same facts block asserts still_there: yes.

Mutation, :263 → "still_there": not moving_now: test_companion.py
still passes and still prints ok. That cell isn't covered. (Flipping it to
a constant False is caught, by test_still_home_after_hours — so the
suite only pins the at-home-still case.)
2. --add writes somewhere different per profile

default_places_file() :149-162 branches on
(expand(hermes_home) / "state").is_dir(). Whether some other feature has
ever created that profile's state/ decides if your --add lands in a
profile-private state/places.json or in the machine-wide
~/.hermes/hermes-companion/places.json.

Same machine, default profile with state/, plus a named profile:

HERMES_HOME=<default>  -> ...\.hermes\state\places.json
HERMES_HOME=<fresh>    -> ~\.hermes\hermes-companion\places.json

Both return rc=0 and both write, so a place saved under one profile is
invisible under the other. The mirror case is worse: with exactly one named
profile carrying state/places.json, the default profile's --add writes
into another profile's directory (:158-161). Note the fallback reaches
into the real home with no prompt — a probe of mine landed a file in
~/.hermes/hermes-companion/ before I routed HERMES_HOME somewhere real.

Smaller one: age_seconds :70-74 returns None on a parse failure and
:211 gps_age = age_seconds(...) or 0 folds that to 0. A corrupt or
absent recorded_at then reports minutes_since_last_move: 0 and
is_stale: no — "just arrived", where Procedure step 2 has the model read
that field as how long they have been there.