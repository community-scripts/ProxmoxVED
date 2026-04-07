#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


PATTERNS = [
    (re.compile(r"\bsshpass\s+-p\s+", re.IGNORECASE), "Use 'sshpass -e' instead of exposing passwords with '-p'."),
    (re.compile(r"\beval\b"), "Avoid eval unless strictly necessary. Add '# security-check: allow-eval' with rationale when required."),
    (re.compile(r"\bcurl\b[^\n|;]*\|\s*(?:bash|sh)\b", re.IGNORECASE), "Avoid piping curl output directly into shell execution."),
    (re.compile(r"\bwget\b[^\n|;]*\|\s*(?:bash|sh)\b", re.IGNORECASE), "Avoid piping wget output directly into shell execution."),
    (re.compile(r"\bchmod\s+777\b"), "Avoid world-writable permissions (chmod 777)."),
]

ALLOW_EVAL_HINT = "security-check: allow-eval"


def read_file_list(path: Path) -> list[Path]:
    files: list[Path] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            files.append(Path(line))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce shell security pattern checks")
    parser.add_argument("--file-list", required=True, help="Path to newline-delimited file list")
    args = parser.parse_args()

    repo_root = Path.cwd()
    files = read_file_list(Path(args.file_list))
    violations: list[str] = []

    for rel in files:
        path = repo_root / rel
        if not path.exists() or path.is_dir():
            continue

        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue

        for idx, line in enumerate(lines, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            for pattern, message in PATTERNS:
                if not pattern.search(line):
                    continue

                if "eval" in pattern.pattern and ALLOW_EVAL_HINT in line:
                    continue

                violations.append(f"{rel}:{idx}: {message} | line: {stripped}")

    if violations:
        print("Security policy violations detected:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print("Security policy checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
