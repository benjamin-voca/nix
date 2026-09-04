#!/usr/bin/env python3
"""
Conservative migration of Nextcloud UltimateBladeGrounds authoring assets
into the farbeam/upg Git working tree.

Phases:
  1) inventory source + destination
  2) dry-run plan (default)
  3) execute copy/normalize only with --apply
  4) never delete source; never overwrite differing files silently

Usage:
  python3 migrate_assets.py --source /path/to/UltimateBladeGrounds \\
                            --extra-source /path/to/Klajdi/files \\
                            --dest /path/to/upg-checkout \\
                            --dry-run

  python3 migrate_assets.py ... --apply
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Iterable

IGNORE_NAMES = {
    ".DS_Store",
    "Thumbs.db",
    "desktop.ini",
}
IGNORE_SUFFIXES = (
    ".blend1",
    ".blend2",
    ".blend3",
    ".blend4",
    ".blend5",
    ".blend@",
)
# Nextcloud conflict / temp leftovers
IGNORE_REGEX = re.compile(
    r"(conflicted copy|\.blend[0-9]$|\.blend@$|\.~[0-9a-f]+$)",
    re.IGNORECASE,
)

# Canonical move slots for characters
MOVES = ["A1", "A2", "A3", "A4", "Idle", "M1", "Special", "U1", "U2", "U3", "U4"]
CATEGORIES = ["Animations", "VFX", "SFX"]
CHARACTERS_HINT = ["Benimaru", "Killua", "Rayne"]

LFS_EXTENSIONS = {
    ".blend",
    ".fbx",
    ".psd",
    ".tga",
    ".exr",
    ".tif",
    ".tiff",
    ".abc",
    ".hip",
    ".hipnc",
    ".ma",
    ".mb",
    ".max",
    ".c4d",
}


@dataclass
class Action:
    kind: str  # copy | skip_identical | conflict_rename | mkdir | ignore | migrate_legacy
    src: str = ""
    dest: str = ""
    note: str = ""


@dataclass
class Plan:
    actions: list[Action] = field(default_factory=list)
    source_files: int = 0
    source_bytes: int = 0
    dest_before_files: int = 0
    conflicts: int = 0
    ignored: int = 0
    copies: int = 0

    def add(self, action: Action) -> None:
        self.actions.append(action)
        if action.kind == "copy":
            self.copies += 1
        elif action.kind == "conflict_rename":
            self.conflicts += 1
            self.copies += 1
        elif action.kind == "ignore":
            self.ignored += 1


def sha256_file(path: Path, chunk: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def should_ignore(path: Path) -> bool:
    name = path.name
    if name in IGNORE_NAMES:
        return True
    if name.startswith("._"):
        return True
    lower = name.lower()
    for suf in IGNORE_SUFFIXES:
        if lower.endswith(suf):
            return True
    if IGNORE_REGEX.search(name):
        return True
    # Nextcloud temp version files like .foo.blend.~abc
    if name.startswith(".") and ".~" in name:
        return True
    return False


def iter_files(root: Path) -> Iterable[Path]:
    for dirpath, dirnames, filenames in os.walk(root):
        # Skip Nextcloud internals if someone pointed at a user home by mistake
        dirnames[:] = [d for d in dirnames if d not in {"files_versions", "files_trashbin", "uploads"}]
        for fn in filenames:
            p = Path(dirpath) / fn
            yield p


def rel(path: Path, root: Path) -> str:
    return str(path.relative_to(root)).replace("\\", "/")


def ensure_canonical_scaffold(dest_root: Path, plan: Plan) -> None:
    """Create Benimaru (and template) move folders without Legacy/."""
    games = ["UltimateBladeGrounds"]
    for game in games:
        for character in ["Benimaru", "Killua", "Rayne", "Template"]:
            for category in CATEGORIES:
                for move in MOVES:
                    for leaf in ("Blender", "Roblox"):
                        d = dest_root / game / character / category / move / leaf
                        plan.add(Action(kind="mkdir", dest=str(d), note="canonical scaffold"))
        # Shared locomotion
        for shared in ("Dash", "Sprint", "Walk"):
            d = dest_root / game / "Shared" / shared
            plan.add(Action(kind="mkdir", dest=str(d), note="shared scaffold"))
        # RIG folders
        for character in ["Benimaru", "Killua", "Rayne"]:
            d = dest_root / game / character / "RIG"
            plan.add(Action(kind="mkdir", dest=str(d), note="rig scaffold"))


def normalize_rel_path(rel_path: str) -> tuple[str, str]:
    """
    Map a source-relative path into a destination-relative path.
    Returns (dest_rel, note).
    Drops nested Legacy/ segments by promoting files into sibling Blender/Roblox
    when possible; otherwise keeps a disambiguated name under the non-Legacy parent.
    """
    parts = rel_path.split("/")

    # Drop worthless folder names
    cleaned: list[str] = []
    for p in parts:
        if p in {"untitled folder", "NiggaBullshitFolderGO"}:
            continue
        cleaned.append(p)
    parts = cleaned

    # Identify Legacy segments
    if "Legacy" in parts:
        # Keep everything before first Legacy as the anchor.
        idx = parts.index("Legacy")
        before = parts[:idx]
        after = parts[idx + 1 :]
        # If after starts with Blender/Roblox, use that.
        # If after is a dump folder of files, try to infer Blender vs Roblox from extension.
        filename = parts[-1]
        ext = Path(filename).suffix.lower()
        leaf = "Blender" if ext in {".blend", ".fbx", ".psd", ".ma", ".mb"} else "Roblox"
        # Prefer existing Blender/Roblox in 'before'
        if before and before[-1] in {"Blender", "Roblox"}:
            dest_parts = before + [filename]
            return "/".join(dest_parts), "legacy-promoted-into-existing-leaf"
        # If before ends with a move (A1 etc), append leaf
        if before and before[-1] in MOVES:
            dest_parts = before + [leaf, filename]
            return "/".join(dest_parts), f"legacy-promoted-to-{leaf}"
        # Otherwise strip Legacy and keep remainder, but avoid Legacy in dest
        dest_parts = before + [p for p in after if p != "Legacy"]
        return "/".join(dest_parts), "legacy-stripped"

    # Scraped Animations dumps → keep under character/Animations/M1/_imported/...
    if "Scraped Animations" in parts or "Scraped Animations 2" in parts:
        return rel_path.replace("Scraped Animations 2", "_imported/ScrapedAnimations").replace(
            "Scraped Animations", "_imported/ScrapedAnimations"
        ), "scraped-import"

    return rel_path, "as-is"


def unique_dest(dest: Path) -> Path:
    if not dest.exists():
        return dest
    stem, suffix = dest.stem, dest.suffix
    parent = dest.parent
    n = 2
    while True:
        candidate = parent / f"{stem}__dup{n}{suffix}"
        if not candidate.exists():
            return candidate
        n += 1


def plan_copy(
    plan: Plan,
    src_file: Path,
    dest_file: Path,
    note: str,
) -> None:
    if dest_file.exists():
        try:
            if sha256_file(src_file) == sha256_file(dest_file):
                plan.add(
                    Action(
                        kind="skip_identical",
                        src=str(src_file),
                        dest=str(dest_file),
                        note=note,
                    )
                )
                return
        except OSError as e:
            plan.add(
                Action(
                    kind="conflict_rename",
                    src=str(src_file),
                    dest=str(unique_dest(dest_file)),
                    note=f"{note}; hash-compare-failed: {e}",
                )
            )
            return
        # Different content — preserve both
        renamed = unique_dest(dest_file)
        plan.add(
            Action(
                kind="conflict_rename",
                src=str(src_file),
                dest=str(renamed),
                note=f"{note}; destination exists with different content",
            )
        )
        return

    plan.add(Action(kind="copy", src=str(src_file), dest=str(dest_file), note=note))


def inventory_source(source: Path, plan: Plan, dest_root: Path, prefix_under_game: str | None = None) -> None:
    game_root_name = "UltimateBladeGrounds"
    for f in iter_files(source):
        if should_ignore(f):
            plan.add(Action(kind="ignore", src=str(f), note="backup/temp/os junk"))
            continue
        plan.source_files += 1
        try:
            plan.source_bytes += f.stat().st_size
        except OSError:
            pass

        rel_path = rel(f, source)
        # If source is already UltimateBladeGrounds, keep structure under dest/UltimateBladeGrounds
        if source.name == game_root_name or (source / "Benimaru").exists() or (source / "Killua").exists():
            dest_rel, note = normalize_rel_path(rel_path)
            dest_file = dest_root / game_root_name / dest_rel
        elif prefix_under_game:
            dest_rel, note = normalize_rel_path(f"{prefix_under_game}/{rel_path}")
            dest_file = dest_root / game_root_name / dest_rel
        else:
            dest_rel, note = normalize_rel_path(rel_path)
            dest_file = dest_root / game_root_name / "_incoming" / dest_rel

        plan_copy(plan, f, dest_file, note)


def map_klajdi_wip(extra: Path, dest_root: Path, plan: Plan) -> None:
    """Place Klajdi root WIP M1 files into Benimaru/Animations/M1."""
    mapping = {
        "second-m1.blend": "Benimaru/Animations/M1/Blender/second-m1.blend",
        "third-m1.blend": "Benimaru/Animations/M1/Blender/third-m1.blend",
        "fourth-m1.blend": "Benimaru/Animations/M1/Blender/fourth-m1.blend",
        "second-m1.rbxanim": "Benimaru/Animations/M1/Roblox/second-m1.rbxanim",
        "third-m1.rbxanim": "Benimaru/Animations/M1/Roblox/third-m1.rbxanim",
        "fourth-m1.rbxanim": "Benimaru/Animations/M1/Roblox/fourth-m1.rbxanim",
    }
    for name, dest_rel in mapping.items():
        src = extra / name
        if not src.exists():
            continue
        if should_ignore(src):
            plan.add(Action(kind="ignore", src=str(src), note="blend backup"))
            continue
        plan.source_files += 1
        try:
            plan.source_bytes += src.stat().st_size
        except OSError:
            pass
        dest = dest_root / "UltimateBladeGrounds" / dest_rel
        plan_copy(plan, src, dest, "klajdi-wip-m1")


def write_gitattributes(dest_root: Path, plan: Plan) -> Path:
    path = dest_root / ".gitattributes"
    existing = path.read_text() if path.exists() else ""
    block = """
# --- UPG authoring assets (managed by upg-assets migration) ---
*.blend filter=lfs diff=lfs merge=lfs -text
*.fbx filter=lfs diff=lfs merge=lfs -text
*.psd filter=lfs diff=lfs merge=lfs -text
*.tga filter=lfs diff=lfs merge=lfs -text
*.exr filter=lfs diff=lfs merge=lfs -text
*.tif filter=lfs diff=lfs merge=lfs -text
*.tiff filter=lfs diff=lfs merge=lfs -text
*.abc filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.png filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.jpg filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.jpeg filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.wav filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.mp3 filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.ogg filter=lfs diff=lfs merge=lfs -text
"""
    if "UPG authoring assets" not in existing:
        plan.add(Action(kind="copy", src="(generated)", dest=str(path), note="append LFS gitattributes"))
        return path
    plan.add(Action(kind="skip_identical", dest=str(path), note="gitattributes already present"))
    return path


def write_gitignore(dest_root: Path, plan: Plan) -> Path:
    path = dest_root / ".gitignore"
    existing = path.read_text() if path.exists() else ""
    block = """
# --- Blender local backups (managed by upg-assets) ---
*.blend1
*.blend2
*.blend3
*.blend4
*.blend5
*.blend@
*.blend[0-9]*

# OS / editor junk in authoring tree
UltimateBladeGrounds/**/.DS_Store
UltimateBladeGrounds/**/Thumbs.db
UltimateBladeGrounds/**/untitled folder/
"""
    if "Blender local backups" not in existing:
        plan.add(Action(kind="copy", src="(generated)", dest=str(path), note="append gitignore backups"))
    else:
        plan.add(Action(kind="skip_identical", dest=str(path), note="gitignore already present"))
    return path


def apply_plan(plan: Plan, dest_root: Path) -> None:
    # Scaffold dirs first
    for a in plan.actions:
        if a.kind == "mkdir":
            Path(a.dest).mkdir(parents=True, exist_ok=True)

    # gitattributes / gitignore
    ga = dest_root / ".gitattributes"
    existing = ga.read_text() if ga.exists() else ""
    if "UPG authoring assets" not in existing:
        with ga.open("a") as f:
            f.write(
                """
# --- UPG authoring assets (managed by upg-assets migration) ---
*.blend filter=lfs diff=lfs merge=lfs -text
*.fbx filter=lfs diff=lfs merge=lfs -text
*.psd filter=lfs diff=lfs merge=lfs -text
*.tga filter=lfs diff=lfs merge=lfs -text
*.exr filter=lfs diff=lfs merge=lfs -text
*.tif filter=lfs diff=lfs merge=lfs -text
*.tiff filter=lfs diff=lfs merge=lfs -text
*.abc filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.png filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.jpg filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.jpeg filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.wav filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.mp3 filter=lfs diff=lfs merge=lfs -text
UltimateBladeGrounds/**/*.ogg filter=lfs diff=lfs merge=lfs -text
"""
            )

    gi = dest_root / ".gitignore"
    existing = gi.read_text() if gi.exists() else ""
    if "Blender local backups" not in existing:
        with gi.open("a") as f:
            f.write(
                """
# --- Blender local backups (managed by upg-assets) ---
*.blend1
*.blend2
*.blend3
*.blend4
*.blend5
*.blend@
*.blend[0-9]*

# OS / editor junk in authoring tree
UltimateBladeGrounds/**/.DS_Store
UltimateBladeGrounds/**/Thumbs.db
UltimateBladeGrounds/**/untitled folder/
"""
            )
        # Also allow UltimateBladeGrounds rbxm despite root ignore of /*.rbxm
        # Root ignore is only /*.rbxm (repo root). Nested paths are fine.

    for a in plan.actions:
        if a.kind in {"copy", "conflict_rename"} and a.src and a.src != "(generated)":
            src = Path(a.src)
            dest = Path(a.dest)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)


def print_summary(plan: Plan, dest_root: Path) -> None:
    print("=== Migration plan summary ===")
    print(f"source_files_considered: {plan.source_files}")
    print(f"source_bytes:            {plan.source_bytes}")
    print(f"copies:                  {plan.copies}")
    print(f"conflicts_renamed:       {plan.conflicts}")
    print(f"ignored:                 {plan.ignored}")
    print(f"actions_total:           {len(plan.actions)}")
    by_kind = defaultdict(int)
    for a in plan.actions:
        by_kind[a.kind] += 1
    print("by_kind:", dict(by_kind))
    print("\n--- actions (first 80) ---")
    for a in plan.actions[:80]:
        print(f"{a.kind:18} {a.src} -> {a.dest} ({a.note})")
    if len(plan.actions) > 80:
        print(f"... {len(plan.actions) - 80} more")

    lfs_dests = [
        a.dest
        for a in plan.actions
        if a.kind in {"copy", "conflict_rename"} and Path(a.dest).suffix.lower() in LFS_EXTENSIONS
    ]
    print(f"\nfiles that will be LFS-tracked by extension: {len(lfs_dests)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--source", required=True, type=Path, help="UltimateBladeGrounds export directory")
    ap.add_argument("--extra-source", type=Path, help="Optional artist home (e.g. Klajdi/files) for WIP")
    ap.add_argument("--dest", required=True, type=Path, help="Git working tree root (farbeam/upg checkout)")
    ap.add_argument("--dry-run", action="store_true", default=True, help="Plan only (default)")
    ap.add_argument("--apply", action="store_true", help="Execute copy operations")
    ap.add_argument("--plan-json", type=Path, help="Write full plan JSON to this path")
    args = ap.parse_args()

    if args.apply:
        args.dry_run = False

    source = args.source.resolve()
    dest = args.dest.resolve()
    if not source.is_dir():
        print(f"ERROR: source not a directory: {source}", file=sys.stderr)
        return 2
    if not dest.is_dir():
        print(f"ERROR: dest not a directory: {dest}", file=sys.stderr)
        return 2
    if not (dest / ".git").exists():
        print(f"ERROR: dest is not a git checkout: {dest}", file=sys.stderr)
        return 2

    plan = Plan()
    plan.dest_before_files = sum(1 for _ in iter_files(dest / "UltimateBladeGrounds")) if (dest / "UltimateBladeGrounds").exists() else 0

    ensure_canonical_scaffold(dest, plan)
    write_gitattributes(dest, plan)
    write_gitignore(dest, plan)
    inventory_source(source, plan, dest)

    if args.extra_source:
        map_klajdi_wip(args.extra_source.resolve(), dest, plan)

    print_summary(plan, dest)

    if args.plan_json:
        payload = {
            "source": str(source),
            "dest": str(dest),
            "summary": {
                "source_files": plan.source_files,
                "source_bytes": plan.source_bytes,
                "copies": plan.copies,
                "conflicts": plan.conflicts,
                "ignored": plan.ignored,
            },
            "actions": [asdict(a) for a in plan.actions],
        }
        args.plan_json.write_text(json.dumps(payload, indent=2))
        print(f"wrote plan json: {args.plan_json}")

    if args.dry_run:
        print("\nDRY-RUN only. Re-run with --apply to execute.")
        return 0

    print("\nApplying...")
    apply_plan(plan, dest)

    # Verification counts
    ubg = dest / "UltimateBladeGrounds"
    dest_files = [p for p in iter_files(ubg) if not should_ignore(p)] if ubg.exists() else []
    dest_bytes = sum(p.stat().st_size for p in dest_files)
    print("=== Post-apply verification ===")
    print(f"dest UltimateBladeGrounds files: {len(dest_files)}")
    print(f"dest UltimateBladeGrounds bytes: {dest_bytes}")
    print(f"source files (non-ignored):      {plan.source_files}")
    print(f"source bytes:                    {plan.source_bytes}")
    print("NOTE: source data was NOT deleted. Verify then remove Nextcloud copies manually later.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
