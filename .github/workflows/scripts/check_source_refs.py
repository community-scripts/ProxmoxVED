#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


SOURCE_RE = re.compile(r"^\s*(?:source|\.)\s+(.+?)\s*(?:#.*)?$")
SC_DIRECTIVE_RE = re.compile(r"#\s*shellcheck\s+source=([^\s]+)")


def normalize_source_token(expr: str) -> str | None:
    expr = expr.strip()
    if not expr:
      return None

    # Skip dynamic process substitution and command substitution forms.
    if expr.startswith("<(") or "$(" in expr:
        return None

    token = expr.split()[0].strip("\"'")
    if not token:
        return None

    # Dynamic variables or common virtual paths can't be statically validated.
    if token.startswith("$"):
        return None
    if token.startswith(("http://", "https://", "/dev/", "/proc/", "-")):
        return None
    if any(ch in token for ch in ["*", "?", "["]):
        return None

    return token


def exists_candidate(repo_root: Path, file_path: Path, token: str) -> bool:
    p = Path(token)
    if p.is_absolute():
        return p.exists()

    candidates = [
        (file_path.parent / p),
        (repo_root / p),
    ]
    return any(c.exists() for c in candidates)


def read_file_list(path: Path) -> list[Path]:
    files: list[Path] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            files.append(Path(line))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate shell source/include references")
    parser.add_argument("--file-list", required=True, help="Path to newline-delimited file list")
    args = parser.parse_args()

    repo_root = Path.cwd()
    files = read_file_list(Path(args.file_list))
    errors: list[str] = []

    for rel in files:
        path = repo_root / rel
        if not path.exists() or path.is_dir():
            continue

        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue

        for idx, line in enumerate(lines, start=1):
            for m in SC_DIRECTIVE_RE.finditer(line):
                target = m.group(1).strip()
                if target.startswith("/"):
                    # Absolute paths in directives can be environment-specific; skip.
                    continue
                if not exists_candidate(repo_root, path, target):
                    errors.append(f"{rel}:{idx}: shellcheck source target not found: {target}")

            source_match = SOURCE_RE.match(line)
            if not source_match:
                continue

            token = normalize_source_token(source_match.group(1))
            if token is None:
                continue

            if not exists_candidate(repo_root, path, token):
                errors.append(f"{rel}:{idx}: source target not found: {token}")

    if errors:
        print("Source/include validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("Source/include validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
