# Fork Changelog

Changes in this fork relative to upstream.

- Styling cleanup across the whole UI
- Knob values snap to whole numbers
- New "Light 1" and "Dark 1" theme variants
- Custom macOS-styled titlebar with traffic-light window controls and rounded window corners
- Audio device selection start page (standalone only)
- Disabled Soundshed API connections (tone sharing, community presets)
  The upstream README states Soundshed's APIs are for their own software only,
  so this fork disables those connections to avoid any ambiguity.
  The TONES button now shows a "Connection to Soundshed servers is disabled
  on this fork." notice.
- macOS Window mode setting (Dock vs Menu bar) — user-selectable in Settings → Appearance
- macOS menu bar status item integration (opt-in via Window mode setting)
- Removed "Show in Dock" toggle (replaced by Window mode setting)
