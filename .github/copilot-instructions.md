# GuitarFX Agent Playbook

## Prime Directives

- Do not write code before stating assumptions.
- Do not claim correctness you haven't verified.
- Do not handle only the happy path.
- Do not leave a mess — clean up after every change.
- Under what conditions does this work?

## Project Map
- C++ core: core/src/ (DSP, presets, controller/dispatcher, resource loading)
- UI: core/ui/ts/ (WebView TypeScript SPA)
- Host integration: juce/ (JUCE standalone/VST3/AU plugin adapter and WebView host)
- Build: CMake + FetchContent; core tests in core/build, JUCE targets in juce/builds
- Docs: docs/ (architecture, data models, UI, network integrations)

## DSP Graph Essentials
- Graph runner: core/src/dsp/SignalGraphExecutor.h with nodes of type amp_nam, cab_ir, eq_parametric, delay_digital, reverb_room, dynamics_gate, etc.
- Effects live in core/src/dsp/effects/; new effects implement EffectProcessor and register via EffectRegistry.
- Validate parameter ranges and resource presence; fail fast with clear errors instead of silent defaults.
- Full spec: docs/signal-chain.md, docs/fx-library.md

## UI ↔ Plugin Messaging
- Messaging flows through core/src/MessageDispatcher.cpp and PluginController::HandleUIMessage().
- Common payloads: state, presetLoaded, loadPreset, setParameter, browseModel, addSignalPathNode, removeSignalPathNode.
- UI bridge lives in core/ui/ts/bridge.ts and core/ui/ts/messages.ts; native host glue is in juce/source/PluginProcessorAdapter.cpp and juce/source/PluginEditor.cpp.
- Keep messages backward compatible; guard against missing fields and unknown message types.
- Full spec: docs/user-interface.md

## Resource References
- ResourceRef supports library refs (resourceType + resourceId), filePath for user files, embeddedId for portable presets.
- When loading, prefer library refs; fall back to file/embedded only when provided. Validate existence and log meaningful errors.
- Full spec: docs/fx-library.md, docs/data-models.md

## Build Quickstart
- Configure the shared core (for tests and core-only work):
	powershell: cmake -S core -B core/build
- Configure the JUCE host (Standalone/VST3/AU):
	powershell: cmake -S juce -B juce/builds -G "Visual Studio 18 2026" -A x64
- Build the host targets:
	Debug Standalone: cmake --build juce/builds --config Debug --target SoundshedGuitar_Standalone
	Debug VST3: cmake --build juce/builds --config Debug --target SoundshedGuitar_VST3
	Release Standalone: cmake --build juce/builds --config Release --target SoundshedGuitar_Standalone
- UI bundle: cd core/ui && npm run build
- UI type-check (no emit): cd core/ui && npm run typecheck
- UI format check: cd core/ui && npm run format:check
- UI format fix: cd core/ui && npm run format

## Testing
- From core/build (Debug only):
	powershell: ctest -C Debug --output-on-failure
- Key suites are defined in core/tests/CMakeLists.txt; common targets include PresetDSPLoadingTests, PresetManagementWorkflowTests, ResourcePreviewWorkflowTests, and SignalGraphExecutorTests.

## Coding Conventions

### C++
- Namespace guitarfx::; require C++20.
- Header guards: `#pragma once` only.
- Naming: classes/structs/methods use PascalCase; member variables use `m` prefix (e.g. `mSampleRate`); static/global constants use `k` prefix (e.g. `kMaxCustomSlots`); locals/params use camelCase.
- `[[nodiscard]]` on all getters and factory functions.
- `const`-correctness: methods, references, and locals all const by default.
- `static_cast` only; never use C-style casts.
- Error handling: `std::optional` for recoverable failures, `bool` for simple success/failure. Catch exceptions only at third-party library boundaries.
- Smart pointers: `std::unique_ptr` for ownership; `std::shared_ptr` rare.
- Keep DSP real-time safe: avoid allocations and locks in audio thread; prefer preallocation and lock-free patterns.

### TypeScript
- `strict: true` with `verbatimModuleSyntax` — use `import type { ... }` for all type-only imports.
- Prefer `interface` for object shapes; use `type` only for unions, aliases, and mapped types.
- State is a single mutable object (`uiState` in `core/ui/ts/state.ts`) with getter/setter wrappers. No Redux, no immutability.
- CSS: always use theme tokens (`var(--color-accent)`, `--modal-bg`, etc.); never hardcode hex colors.
- Alpine.js is used for reactive DOM bindings; it reads from the TS layer, not the reverse.

### JSON
- Serialization uses nlohmann::json; maintain stable field names and defaults.
- Parameter IDs must stay aligned with the UI message contract in `core/ui/ts/messages.ts`.

## Formatting & Tooling
- C++ formatting: `.clang-format` at repo root (Allman brace style, 4-space indent).
- UI formatting: `core/ui/.prettierrc` (2-space indent, semicolons, trailing commas).
- Editor settings: `.editorconfig` at repo root (LF line endings, UTF-8).
- Run `ctest -C Debug --output-on-failure` before declaring C++ changes complete.
- Run `npm run build` before declaring UI changes complete.

## Code Cleanliness

These rules apply to all changes. Violating them creates technical debt.

- **No commented-out code** — delete it. Git history preserves the original.
- **No dead code paths** — unreachable branches, unused functions, unused variables.
- **No magic numbers** — use named `constexpr`/`const` constants.
- **No `any` in TypeScript** — use proper types. The only exception is Alpine.js externals (`(window as any).Alpine`).
- **No `TODO` without an associated issue** — if it's worth tracking, create an issue and reference it.
- **No empty catch blocks** — at minimum log the error.
- **No duplication** — extract shared logic rather than copy-pasting.
- **Validate inputs; fail fast** — check parameter ranges, resource presence, and graph validity before processing.
- **Keep files focused** — one primary concern per file. Large modules should be split.
- **Remove unused imports and declarations** — TypeScript strict mode helps but manual cleanup is still needed.
- **Backward compatibility** — presets, resources, and UI messages must remain loadable across versions.

## Key Files
- Controller + message routing: core/src/PluginController.cpp, core/src/MessageDispatcher.cpp
- Effect base + registry: core/src/dsp/EffectProcessor.h, core/src/dsp/EffectRegistry.h
- Preset types: core/src/presets/PresetTypes.h
- Graph executor: core/src/dsp/SignalGraphExecutor.h
- Config/branding: core/config/GuitarFXConfig.h
- UI entry: core/ui/ts/main.ts
- JUCE host glue: juce/source/PluginProcessorAdapter.cpp, juce/source/PluginEditor.cpp

## Documentation
- Architecture: docs/architecture-overview.md
- Signal chain: docs/signal-chain.md
- Effects/resources: docs/fx-library.md
- Presets/storage: docs/data-models.md
- UI/messaging: docs/user-interface.md
- Network / remote integrations: docs/network-api.md
- Theming: docs/theme-system.md
- PRD: docs/prd/PRD.md

## Change Checklist
- Assumptions stated and confirmed where needed.
- Error paths covered; log actionable messages.
- Code cleanliness rules respected (no dead code, no magic numbers, no `any`, etc.).
- C++ build + tests pass: `ctest -C Debug --output-on-failure`
- UI build passes: `npm run build`
- UI type-check passes: `npm run typecheck`
- Formatting consistent: run formatters before declaring done.
- Backward compatibility considered for presets, resources, and UI messages.
- Docs or comments updated when behavior changes.

## Communication
- Keep updates concise and scoped; reference affected files.
- If blockers or unexpected changes appear, pause and ask before proceeding.

## Git Workflow
- **Never auto-commit.** Always wait for explicit user approval before committing changes to git.
- Users control the commit lifecycle: review diffs in the UI, approve changes, and trigger commits manually.
- If you need to commit as part of a task, ask the user first and show them the diff before proceeding.
