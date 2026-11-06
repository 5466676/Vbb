"""Pure game logic.

Rules for this package:
- No I/O, no network, no clocks, no global randomness.
- Everything goes through ``apply(state, action) -> (new_state, events)``.
- All randomness comes from the seeded RNG stored inside ``MatchState``.
"""
