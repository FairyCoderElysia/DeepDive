# Godot Engine — Version Reference

| Field | Value |
|-------|-------|
| **Engine Version** | Godot 4.7.2 |
| **Installed at pin time** | `4.7.2.stable.official.ed1daf0bf` — probe **ran**: bare `godot --version` (bare `godot` resolves via a hardlink shim in `~/.local/bin`, so `commands.*` use bare `godot` and carry no local path) |
| **Release Date** | 18 August 2026 (4.7.2 stable) |
| **Project Pinned** | 2026-10-02 |
| **Last Docs Verified** | 2026-10-02 |
| **LLM Knowledge Cutoff** | May 2025 |

## Knowledge Gap Warning

The LLM's training data likely covers Godot up to ~4.3. Versions 4.4, 4.5, 4.6,
**4.7** and **4.7.2** introduced changes the model does NOT know about. Always
cross-reference this directory before suggesting Godot API calls.

## Installed-Version Gap Warning

**Pinned == installed on this project (4.7.2), so there is NO installed-version gap.**
The reference set is *not* ahead of the editor, so a version-qualified claim taken
from these files should compile locally.

> Keep this paragraph honest if the pin ever moves. The section exists because the
> reverse gap is real: `/setup-engine` §3 can deliberately pin a version *newer*
> than the installed editor, and an agent citing the reference correctly would then
> emit APIs that do not compile locally. `NOT DETERMINED` means the gap is unknown,
> not absent.

## Post-Cutoff Version Timeline

| Version | Release | Risk Level | Key Theme |
|---------|---------|------------|-----------|
| 4.4 | ~Mid 2025 | MEDIUM | Jolt physics option, FileAccess return types, shader texture type changes |
| 4.5 | ~Late 2025 | HIGH | Accessibility (AccessKit), variadic args, @abstract, shader baker, SMAA |
| 4.6 | Jan 2026 | HIGH | Jolt default, glow rework, D3D12 default on Windows, IK restored |
| **4.7** | **18 Jun 2026** | **HIGH** | **`AnimationNodeBlendSpace*.sync_mode` enum replaces the `sync` bool; `CanvasItem` line AA feather removed; mouse/keyboard device-ID constants; GDScript typed-return inheritance now requires an explicit `return`; macOS 11 minimum; new-project stretch defaults changed** |
| **4.7.2** | **18 Aug 2026** | **HIGH** | **Maintenance release (stable). Specific fixes: `NOT SOURCEABLE` — see the note below.** |

> **4.7 / 4.7.1 / 4.7.2 maintenance specifics are `NOT SOURCEABLE` in this run.**
> Only the version's **existence and date** were verified
> (`https://godotengine.org/versions.json`). The maintenance release notes page
> (`https://godotengine.org/article/maintenance-release-godot-4-7-2/`) was **not
> fetched**, so **no claim about what 4.7.1 or 4.7.2 changed is recorded here**.
> Treat 4.7.2 as *"4.7 plus unlisted maintenance fixes."* Run
> `/setup-engine refresh` to source it properly.

## Scope Note — where the 4.7 delta lives

The `modules/` files in this directory describe subsystems **up to 4.6** (they
arrive from the CCGS template's curated set, which v2 had never received until
this run). The **4.7 delta is recorded in the three top-level files**:
`breaking-changes.md § 4.6 → 4.7` · `deprecated-apis.md § 4.6 → 4.7` ·
`current-best-practices.md § 4.7`. It was deliberately **not** duplicated into
`modules/` — one source of truth beats four paraphrases.

**Before trusting a `modules/` claim on an affected subsystem** (input, physics,
rendering, ui, animation, audio, core), cross-check it against
`breaking-changes.md § 4.6 → 4.7` first.

## Verified Sources

Everything below was **fetched in this run (2026-10-02)** unless explicitly marked
as a *template baseline* (i.e. carried over from the CCGS template and NOT
re-verified this run — do not treat those as freshly confirmed).

- **Godot docs source repo (authoritative source pointed at by the user):**
  https://github.com/godotengine/godot-docs
- **4.6 → 4.7 migration guide — raw `.rst`, fetched this run:**
  https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/migrating/upgrading_to_godot_4.7.rst
  (rendered equivalent: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.7.html)
  > The `.rst` is the **more complete** source: the `AnimationNodeBlendSpace*.sync_mode`
  > behavior change and the macOS 11 minimum both appear here but were **absent from
  > the rendered HTML** when checked in the same run.
- **Version list & release dates — fetched this run:** https://godotengine.org/versions.json
- *Template baseline, NOT re-fetched this run:*
  - Official docs: https://docs.godotengine.org/en/stable/
  - 4.5→4.6 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.6.html
  - 4.4→4.5 migration: https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html
  - Changelog: https://github.com/godotengine/godot/blob/master/CHANGELOG.md
  - Release notes 4.6: https://godotengine.org/releases/4.6/
