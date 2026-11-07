"""Army definitions and their perk values (see GAME_RULES §2.1).

Perk numbers are kept here so balance tuning touches one file.
"""

from __future__ import annotations

from enum import StrEnum


class Army(StrEnum):
    ISLAMIC = "islamic"  # الفتوحات الإسلامية
    AYYUBID = "ayyubid"  # الأيوبيون
    CRUSADER = "crusader"  # الصليبيون
    ROMAN = "roman"  # الرومان
    PHARAOH = "pharaoh"  # الفراعنة
    MONGOL = "mongol"  # المغول
    OTTOMAN = "ottoman"  # العثمانيون
    WW2 = "ww2"  # الحرب العالمية الثانية


# --- passive perks -------------------------------------------------------------------------
ISLAMIC_CAPTURE_BONUS = 50
AYYUBID_BASE_VALUE = 1100
CRUSADER_HOLD_GAIN = 150
ROMAN_BATTLE_START_GAIN = 25
PHARAOH_NUMERIC_EXTRA_MS = 2000
MONGOL_ATTACK_TIME_BONUS_MS = 200
OTTOMAN_CAPTURE_GAIN = 150

# --- active abilities ----------------------------------------------------------------------
PHARAOH_PYRAMID_GAIN = 300
CRUSADER_SIEGE_TOWERS = 2
