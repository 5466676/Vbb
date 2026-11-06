"""Room lifecycle, timers, Redis state and the WebSocket hub.

Timers live here, not in the engine: when a deadline passes the room feeds a
``Timeout`` action into the engine.
"""
