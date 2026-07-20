#!/usr/bin/env python3
"""
Migrate hardcoded border-radius values to CSS custom properties.

Mapping:
  1-2px  -> var(--radius-sm)
  3-5px  -> var(--radius-md)
  6-7px  -> var(--radius-lg)
  8-16px -> var(--radius-xl)
  20px   -> var(--radius-full)
  999px  -> var(--radius-full)
  50%    -> var(--radius-round)
  0      -> left as-is
  already using var() -> left as-is
  dynamic ${...}     -> left as-is
"""

import re
import sys
from pathlib import Path

UI_CSS_DIR = Path("core/ui/css")
UI_TS_DIR = Path("core/ui/ts")

# radius value -> variable mapping (ordered longest first to avoid partial matches)
RADIUS_MAP = [
    ("999px", "var(--radius-full)"),
    ("20px", "var(--radius-full)"),
    ("16px", "var(--radius-xl)"),
    ("14px", "var(--radius-xl)"),
    ("12px", "var(--radius-xl)"),
    ("10px", "var(--radius-xl)"),
    ("8px", "var(--radius-xl)"),
    ("7px", "var(--radius-lg)"),
    ("6px", "var(--radius-lg)"),
    ("5px", "var(--radius-md)"),
    ("4px", "var(--radius-md)"),
    ("3px", "var(--radius-md)"),
    ("2px", "var(--radius-sm)"),
    ("1px", "var(--radius-sm)"),
    ("50%", "var(--radius-round)"),
]

# Files to process (relative to repo root)
CSS_FILES = [
    "base.css",
    "components.css",
    "controls.css",
    "modals.css",
    "signal-path.css",
    "tone-sharing.css",
    "navigation.css",
    "advanced-panel.css",
    "settings.css",
    "fx-library.css",
    "layout-designer.css",
    "performance-pads.css",
    "preset-library.css",
    "jam.css",
    "amp.css",
    "effects.css",
]

TS_FILES = [
    "updateCheck.ts",
]


def is_already_variable(value: str) -> bool:
    """Check if value already uses a CSS variable or is dynamic."""
    stripped = value.strip().rstrip(";").rstrip("!important").strip()
    if stripped.startswith("var("):
        return True
    if "${" in stripped:
        return True
    return False


def is_zero(value: str) -> bool:
    """Check if value is just 0 or 0 0 ..."""
    parts = value.strip().rstrip(";").rstrip("!important").strip().split()
    return all(p == "0" for p in parts)


def replace_radius_value(value: str) -> str:
    """Replace hardcoded radius values in a single value string."""
    for old, new in RADIUS_MAP:
        if value == old:
            return new
    return value


def split_and_replace(value: str) -> str:
    """Split multi-value border-radius and replace each px value."""
    parts = value.split()
    replaced = [replace_radius_value(p) for p in parts]
    return " ".join(replaced)


def process_css_content(content: str) -> str:
    """Process CSS file content, replacing border-radius values."""
    lines = content.split("\n")
    result = []

    for line in lines:
        # Skip lines where border-radius is a property being transitioned (not a value assignment)
        if re.search(r'transition:\s*.*\bborder-radius\b', line):
            result.append(line)
            continue

        # Handle border-radius declarations
        if re.search(r'border-radius\s*:', line):
            # Check for dynamic template values
            if "${" in line:
                result.append(line)
                continue

            # Check for already-var values
            if "var(" in line:
                result.append(line)
                continue

            # Replace the value(s) after border-radius:
            # Match: border-radius: <value>;<value>; or border-radius: <value> !important;
            def replace_border_radius(m):
                prefix = m.group(1)
                value_part = m.group(2).strip()
                suffix = m.group(3)  # ; or !important;

                if is_already_variable(value_part) or is_zero(value_part):
                    return m.group(0)

                new_value = split_and_replace(value_part)
                return f"{prefix}{new_value}{suffix}"

            new_line = re.sub(
                r'(border-radius\s*:\s*)([^;]+?)(\s*;\s*|\s*!important\s*;\s*)$',
                replace_border_radius,
                line
            )
            if new_line == line:
                # Try alternate pattern for lines without trailing semicolon (inside HTML style attrs etc.)
                new_line = re.sub(
                    r'(border-radius\s*:\s*)([^";]+?)(")',
                    lambda m: f"{m.group(1)}{split_and_replace(m.group(2).strip())}{m.group(3)}",
                    line
                )
            result.append(new_line)
            continue

        # Handle clip-path with round value
        if "round " in line and "clip-path" in line:
            def replace_round(m):
                val = m.group(1)
                for old, new in RADIUS_MAP:
                    if val == old:
                        return f"round {new}"
                return m.group(0)

            new_line = re.sub(r'round\s+(\d+px)', replace_round, line)
            result.append(new_line)
            continue

        result.append(line)

    return "\n".join(result)


def process_ts_content(content: str) -> str:
    """Process TS file content, replacing hardcoded border-radius values in style strings."""
    lines = content.split("\n")
    result = []

    for line in lines:
        if "border-radius:" not in line:
            result.append(line)
            continue

        # Skip dynamic template values
        if "${" in line:
            result.append(line)
            continue

        # Skip already-variable
        if "var(" in line:
            result.append(line)
            continue

        def replace_ts(m):
            prefix = m.group(1)
            value_part = m.group(2).strip()
            suffix = m.group(3)

            if is_already_variable(value_part) or is_zero(value_part):
                return m.group(0)

            new_value = split_and_replace(value_part)
            return f"{prefix}{new_value}{suffix}"

        new_line = re.sub(
            r'(border-radius\s*:\s*)([^;";}]+?)(\s*[;"}])',
            replace_ts,
            line
        )
        result.append(new_line)

    return "\n".join(result)


def main():
    root = Path(__file__).resolve().parent.parent
    changed = []

    # Process CSS files
    css_dir = root / "core/ui/css"
    for fname in CSS_FILES:
        fpath = css_dir / fname
        if not fpath.exists():
            print(f"WARNING: {fpath} not found, skipping")
            continue

        original = fpath.read_text()
        updated = process_css_content(original)
        if updated != original:
            fpath.write_text(updated)
            changed.append(str(fpath.relative_to(root)))
            print(f"  MODIFIED: {fpath.relative_to(root)}")
        else:
            print(f"  UNCHANGED: {fpath.relative_to(root)}")

    # Process TS files
    ts_dir = root / "core/ui/ts"
    for fname in TS_FILES:
        fpath = ts_dir / fname
        if not fpath.exists():
            print(f"WARNING: {fpath} not found, skipping")
            continue

        original = fpath.read_text()
        updated = process_ts_content(original)
        if updated != original:
            fpath.write_text(updated)
            changed.append(str(fpath.relative_to(root)))
            print(f"  MODIFIED: {fpath.relative_to(root)}")
        else:
            print(f"  UNCHANGED: {fpath.relative_to(root)}")

    print(f"\nDone. {'No changes.' if not changed else 'Changed files: ' + ', '.join(changed)}")


if __name__ == "__main__":
    main()
