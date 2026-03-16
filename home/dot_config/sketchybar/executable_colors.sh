#!/bin/bash

# ── Catppuccin Mocha ─────────────────────────────────────────
# Format sketchybar : 0xAARRGGBB

# Base palette
export BASE=0xff1e1e2e
export MANTLE=0xff181825
export CRUST=0xff11111b
export SURFACE0=0xff313244
export SURFACE1=0xff45475a
export OVERLAY0=0xff6c7086
export OVERLAY1=0xff7f849c
export TEXT=0xffcdd6f4
export SUBTEXT0=0xffa6adc8
export SUBTEXT1=0xffbac2de

# Accent colors
export BLUE=0xff89b4fa
export GREEN=0xffa6e3a1
export PEACH=0xfffab387
export RED=0xfff38ba8
export YELLOW=0xfff9e2af
export TEAL=0xff94e2d5
export MAUVE=0xffcba6f7
export PINK=0xfff5c2e7
export SKY=0xff89dceb
export LAVENDER=0xffb4befe

# ── Semantic tokens ──────────────────────────────────────────
# Bar
export BAR_COLOR=0xd91e1e2e           # base @ 85%
export BAR_BORDER_COLOR=0x2689b4fa    # blue @ 15%

# Items (pills)
export ITEM_BG_COLOR=0x99313244       # surface0 @ 60%

# Text
export ICON_COLOR=$TEXT
export LABEL_COLOR=$TEXT

# Active workspace / Front app
export ACCENT_COLOR=$BLUE
export ACCENT_BG=0x2689b4fa           # blue @ 15%

# Muted (inactive)
export MUTED_COLOR=$OVERLAY0
