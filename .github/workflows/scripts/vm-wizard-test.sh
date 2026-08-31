#!/usr/bin/env bash
#
# Exercises the settings path of every VM script without a Proxmox host, which
# nothing did before: bash-syntax.yml only parses, and the wizard needs a tty.
#
#   A  Run default_settings and confirm it leaves nothing the script later uses.
#   B  Flag variables advanced_settings reads but only default_settings writes.
#      That was the "User exited script" report: an empty $DISK_SIZE prefill.
#
set -uo pipefail

CORE="${CORE:-.core/pve/vm-core.func}"
VM_DIR="${VM_DIR:-vm}"

# Tooling rather than a catalog entry; no wizard worth testing.
EXCLUDE="vm-manager"

fail=0
checked=0

for script in "$VM_DIR"/*.sh; do
  slug=$(basename "$script" .sh)
  case " $EXCLUDE " in *" $slug "*) continue ;; esac
  grep -q "vm_prompt_vmid\|vm_start_script" "$script" || continue
  checked=$((checked + 1))

  # ---- A: default_settings has to stand on its own -------------------------
  # Run it for real in a subshell, with core loaded from the checkout and the
  # few host commands stubbed. Anything it forgets shows up as an empty value.
  out=$(
    set +e
    # shellcheck disable=SC1090
    source "$CORE" >/dev/null 2>&1
    get_valid_nextid() { echo 100; }
    pct() { return 1; }
    qm() { return 1; }
    GEN_MAC="02:00:00:00:00:01"
    APP="$slug"

    # Only that one function, so nothing else in the script runs.
    eval "$(awk '/^(function )?default_settings\(\)/,/^}/' "$script")"
    if ! declare -f default_settings >/dev/null 2>&1; then
      echo "NO_DEFAULT_SETTINGS"
      exit 0
    fi
    default_settings >/dev/null 2>&1

    missing=""
    for v in VMID DISK_SIZE HN CORE_COUNT RAM_SIZE BRG MAC START_VM METHOD; do
      [[ -z "${!v:-}" ]] && missing="$missing $v"
    done
    echo "MISSING:${missing}"
  )

  case "$out" in
  NO_DEFAULT_SETTINGS)
    echo "::warning file=$script::no default_settings, skipped"
    continue
    ;;
  MISSING:) ;;
  MISSING:*)
    echo "::error file=$script::default_settings leaves these unset:${out#MISSING:}"
    fail=1
    ;;
  esac

  # ---- B: advanced must not lean on default --------------------------------
  adv=$(awk '/^(function )?advanced_settings\(\)/,/^}/' "$script")
  [[ -z "$adv" ]] && continue

  reads=$(grep -oP '\$\{?\K[A-Z][A-Z0-9_]*' <<<"$adv" | sort -u)
  writes=$(grep -oP '^\s*\K[A-Z][A-Z0-9_]*(?==)' <<<"$adv" | sort -u)
  dwrites=$(awk '/^(function )?default_settings\(\)/,/^}/' "$script" |
    grep -oP '^\s*\K[A-Z][A-Z0-9_]*(?==)' | sort -u)

  for v in $(comm -12 <(echo "$reads") <(echo "$dwrites")); do
    grep -qx "$v" <<<"$writes" && continue
    # Supplying a default inline is exactly the fix, so ${VAR:-something} passes.
    grep -q "\${$v:-" <<<"$adv" && continue
    echo "::error file=$script::advanced_settings reads \$$v, which only default_settings assigns -- it will be empty on the advanced path"
    fail=1
  done
done

if [[ $fail -eq 0 ]]; then
  echo "Settings path checked for $checked scripts: defaults complete, advanced self-contained."
fi
exit $fail
