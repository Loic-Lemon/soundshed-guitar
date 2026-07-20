# Fork Changelog

Changes in this fork relative to upstream.

- Styling cleanup across the whole UI
- Knob values snap to whole numbers
- New "Light 1" and "Dark 1" theme variants
- Frameless standalone window (no title bar)
- Audio device selection start page (standalone only)
- Disabled Soundshed API connections (tone sharing, community presets)
  The upstream README states Soundshed's APIs are for their own software only,
  so this fork disables those connections to avoid any ambiguity.
  The TONES button now shows a "Connection to Soundshed servers is disabled
  on this fork." notice.
