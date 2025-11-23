#!/usr/bin/env python3
"""
Build.func Optimizer
====================
Optimizes the build.func file by:
- Removing duplicate functions
- Sorting and grouping functions logically
- Adding section headers
- Improving readability
"""

import re
import sys
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Dict

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Define function groups in desired order
FUNCTION_GROUPS = {
    "CORE_INIT": {
        "title": "CORE INITIALIZATION & VARIABLES",
        "functions": [
            "variables",
        ]
    },
    "DEPENDENCIES": {
        "title": "DEPENDENCY LOADING",
        "functions": [
            # Bootstrap loader section (commented code)
        ]
    },
    "VALIDATION": {
        "title": "SYSTEM VALIDATION & CHECKS",
        "functions": [
            "maxkeys_check",
            "check_container_resources",
            "check_container_storage",
            "check_nvidia_host_setup",
            "check_storage_support",
        ]
    },
    "NETWORK": {
        "title": "NETWORK & IP MANAGEMENT",
        "functions": [
            "get_current_ip",
            "update_motd_ip",
        ]
    },
    "SSH": {
        "title": "SSH KEY MANAGEMENT",
        "functions": [
            "find_host_ssh_keys",
            "ssh_discover_default_files",
            "ssh_extract_keys_from_file",
            "ssh_build_choices_from_files",
            "configure_ssh_settings",
            "install_ssh_keys_into_ct",
        ]
    },
    "SETTINGS": {
        "title": "SETTINGS & CONFIGURATION",
        "functions": [
            "base_settings",
            "echo_default",
            "exit_script",
            "advanced_settings",
            "diagnostics_check",
            "diagnostics_menu",
            "default_var_settings",
            "ensure_global_default_vars_file",
            "settings_menu",
            "edit_default_storage",
        ]
    },
    "DEFAULTS": {
        "title": "DEFAULTS MANAGEMENT (VAR_* FILES)",
        "functions": [
            "get_app_defaults_path",
            "_is_whitelisted_key",
            "_sanitize_value",
            "_load_vars_file",
            "_load_vars_file_to_map",
            "_build_vars_diff",
            "_build_current_app_vars_tmp",
            "maybe_offer_save_app_defaults",
            "ensure_storage_selection_for_vars_file",
        ]
    },
    "STORAGE": {
        "title": "STORAGE DISCOVERY & SELECTION",
        "functions": [
            "resolve_storage_preselect",
            "select_storage",
            "choose_and_set_storage_for_file",
            "_write_storage_to_vars",
        ]
    },
    "GPU": {
        "title": "GPU & HARDWARE PASSTHROUGH",
        "functions": [
            "is_gpu_app",
            "detect_gpu_devices",
            "configure_gpu_passthrough",
            "configure_usb_passthrough",
            "configure_additional_devices",
            "fix_gpu_gids",
            "get_container_gid",
        ]
    },
    "CONTAINER": {
        "title": "CONTAINER LIFECYCLE & CREATION",
        "functions": [
            "create_lxc_container",
            "offer_lxc_stack_upgrade_and_maybe_retry",
            "parse_template_osver",
            "pkg_ver",
            "pkg_cand",
            "ver_ge",
            "ver_gt",
            "ver_lt",
            "build_container",
            "destroy_lxc",
            "description",
        ]
    },
    "MAIN": {
        "title": "MAIN ENTRY POINTS & ERROR HANDLING",
        "functions": [
            "install_script",
            "start",
            "api_exit_script",
        ]
    },
}

# Functions to exclude from duplication check (intentionally similar)
EXCLUDE_FROM_DEDUP = {
    "_load_vars_file",
    "_load_vars_file_to_map",
}

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

def extract_functions(content: str) -> Dict[str, Tuple[str, int, int]]:
    """
    Extract all function definitions from the content.
    Returns dict: {function_name: (full_code, start_line, end_line)}
    """
    functions = {}
    lines = content.split('\n')

    i = 0
    while i < len(lines):
        line = lines[i]

        # Match function definition: function_name() {
        match = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\)\s*\{', line)
        if match:
            func_name = match.group(1)
            start_line = i

            # Find function end by counting braces
            brace_count = 1
            func_lines = [line]
            i += 1

            while i < len(lines) and brace_count > 0:
                current_line = lines[i]
                func_lines.append(current_line)

                # Count braces (simple method, doesn't handle strings/comments perfectly)
                brace_count += current_line.count('{') - current_line.count('}')
                i += 1

            end_line = i
            functions[func_name] = ('\n'.join(func_lines), start_line, end_line)
            continue

        i += 1

    return functions

def extract_header_comments(content: str, func_name: str, func_code: str) -> str:
    """Extract comment block before function if exists"""
    lines = content.split('\n')

    # Find function start in original content
    for i, line in enumerate(lines):
        if line.strip().startswith(f"{func_name}()"):
            # Look backwards for comment block
            comments = []
            j = i - 1
            while j >= 0:
                prev_line = lines[j]
                stripped = prev_line.strip()

                # SKIP section headers and copyright - we add our own
                if (stripped.startswith('# ===') or
                    stripped.startswith('#!/usr/bin/env') or
                    'Copyright' in stripped or
                    'Author:' in stripped or
                    'License:' in stripped or
                    'Revision:' in stripped or
                    'SECTION' in stripped):
                    j -= 1
                    continue

                # Include function-specific comment lines
                if (stripped.startswith('# ---') or
                    stripped.startswith('#')):
                    comments.insert(0, prev_line)
                    j -= 1
                elif stripped == '':
                    # Keep collecting through empty lines
                    comments.insert(0, prev_line)
                    j -= 1
                else:
                    break

            # Remove leading empty lines from comments
            while comments and comments[0].strip() == '':
                comments.pop(0)

            # Remove trailing empty lines from comments
            while comments and comments[-1].strip() == '':
                comments.pop()

            if comments:
                return '\n'.join(comments) + '\n'

    return ''

def find_duplicate_functions(functions: Dict[str, Tuple[str, int, int]]) -> List[str]:
    """Find duplicate function definitions"""
    seen = {}
    duplicates = []

    for func_name, (code, start, end) in functions.items():
        if func_name in EXCLUDE_FROM_DEDUP:
            continue

        # Normalize code for comparison (remove whitespace variations)
        normalized = re.sub(r'\s+', ' ', code).strip()

        if normalized in seen:
            duplicates.append(func_name)
            print(f"  ⚠️  Duplicate found: {func_name} (also defined as {seen[normalized]})")
        else:
            seen[normalized] = func_name

    return duplicates

def create_section_header(title: str) -> str:
    """Create a formatted section header"""
    return f"""
# ==============================================================================
# {title}
# ==============================================================================
"""

def get_function_group(func_name: str) -> str:
    """Determine which group a function belongs to"""
    for group_key, group_data in FUNCTION_GROUPS.items():
        if func_name in group_data["functions"]:
            return group_key
    return "UNKNOWN"

# ==============================================================================
# MAIN OPTIMIZATION LOGIC
# ==============================================================================

def optimize_build_func(input_file: Path, output_file: Path):
    """Main optimization function"""

    print("=" * 80)
    print("BUILD.FUNC OPTIMIZER")
    print("=" * 80)
    print()

    # Read input file
    print(f"📖 Reading: {input_file}")
    content = input_file.read_text(encoding='utf-8')
    original_lines = len(content.split('\n'))
    print(f"   Lines: {original_lines:,}")
    print()

    # Extract functions
    print("🔍 Extracting functions...")
    functions = extract_functions(content)
    print(f"   Found {len(functions)} functions")
    print()

    # Find duplicates
    print("🔎 Checking for duplicates...")
    duplicates = find_duplicate_functions(functions)
    if duplicates:
        print(f"   Found {len(duplicates)} duplicate(s)")
    else:
        print("   ✓ No duplicates found")
    print()

    # Extract header (copyright, etc)
    print("📝 Extracting file header...")
    lines = content.split('\n')
    header_lines = []

    # Extract only the first copyright block
    in_header = True
    for i, line in enumerate(lines):
        if in_header:
            # Keep copyright and license lines
            if (line.strip().startswith('#!') or
                line.strip().startswith('# Copyright') or
                line.strip().startswith('# Author:') or
                line.strip().startswith('# License:') or
                line.strip().startswith('# Revision:') or
                line.strip() == ''):
                header_lines.append(line)
            else:
                in_header = False
                break

    # Remove trailing empty lines
    while header_lines and header_lines[-1].strip() == '':
        header_lines.pop()

    header = '\n'.join(header_lines)
    print()

    # Build optimized content
    print("🔨 Building optimized structure...")

    optimized_parts = [header]

    # Group functions
    grouped_functions = {key: [] for key in FUNCTION_GROUPS.keys()}
    grouped_functions["UNKNOWN"] = []

    for func_name, (func_code, start, end) in functions.items():
        if func_name in duplicates:
            continue  # Skip duplicates

        group = get_function_group(func_name)

        # Extract comments before function
        comments = extract_header_comments(content, func_name, func_code)

        grouped_functions[group].append((func_name, comments + func_code))

    # Add grouped sections
    for group_key, group_data in FUNCTION_GROUPS.items():
        if grouped_functions[group_key]:
            optimized_parts.append(create_section_header(group_data["title"]))

            for func_name, func_code in grouped_functions[group_key]:
                optimized_parts.append(func_code)
                optimized_parts.append('')  # Empty line between functions

    # Add unknown functions at the end
    if grouped_functions["UNKNOWN"]:
        optimized_parts.append(create_section_header("UNCATEGORIZED FUNCTIONS"))
        print(f"   ⚠️  {len(grouped_functions['UNKNOWN'])} uncategorized functions:")
        for func_name, func_code in grouped_functions["UNKNOWN"]:
            print(f"      - {func_name}")
            optimized_parts.append(func_code)
            optimized_parts.append('')

    # Add any remaining non-function code (bootstrap, source commands, traps, etc)
    print("📌 Adding remaining code...")

    # Extract bootstrap/source section
    bootstrap_lines = []
    trap_lines = []
    other_lines = []

    in_function = False
    brace_count = 0
    in_bootstrap_comment = False

    for line in lines:
        stripped = line.strip()

        # Skip the header we already extracted
        if (stripped.startswith('#!/usr/bin/env bash') or
            stripped.startswith('# Copyright') or
            stripped.startswith('# Author:') or
            stripped.startswith('# License:') or
            stripped.startswith('# Revision:')):
            continue

        # Check if we're in a function
        if re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{', line):
            in_function = True
            brace_count = 1
        elif in_function:
            brace_count += line.count('{') - line.count('}')
            if brace_count == 0:
                in_function = False
        elif not in_function:
            # Collect non-function lines

            # Bootstrap/loader section
            if ('Community-Scripts bootstrap' in line or
                'Load core' in line or
                in_bootstrap_comment):
                bootstrap_lines.append(line)
                if '# ---' in line or '# ===' in line:
                    in_bootstrap_comment = not in_bootstrap_comment
                continue

            # Source commands
            if (stripped.startswith('source <(') or
                stripped.startswith('if command -v curl') or
                stripped.startswith('elif command -v wget') or
                'load_functions' in stripped or
                'catch_errors' in stripped):
                bootstrap_lines.append(line)
                continue

            # Traps
            if stripped.startswith('trap '):
                trap_lines.append(line)
                continue

            # VAR_WHITELIST declaration
            if 'declare -ag VAR_WHITELIST' in line or (other_lines and 'VAR_WHITELIST' in other_lines[-1]):
                other_lines.append(line)
                continue

            # Empty lines between sections - keep some
            if stripped == '' and (bootstrap_lines or trap_lines or other_lines):
                if bootstrap_lines and bootstrap_lines[-1].strip() != '':
                    bootstrap_lines.append(line)
                elif trap_lines and trap_lines[-1].strip() != '':
                    trap_lines.append(line)

    # Add bootstrap section if exists
    if bootstrap_lines:
        optimized_parts.append(create_section_header("DEPENDENCY LOADING"))
        optimized_parts.extend(bootstrap_lines)
        optimized_parts.append('')

    # Add other declarations
    if other_lines:
        optimized_parts.extend(other_lines)
        optimized_parts.append('')

    # Write output
    optimized_content = '\n'.join(optimized_parts)
    optimized_lines = len(optimized_content.split('\n'))

    print()
    print(f"💾 Writing optimized file: {output_file}")
    output_file.write_text(optimized_content, encoding='utf-8')

    print()
    print("=" * 80)
    print("✅ OPTIMIZATION COMPLETE")
    print("=" * 80)
    print(f"Original lines:  {original_lines:,}")
    print(f"Optimized lines: {optimized_lines:,}")
    print(f"Difference:      {original_lines - optimized_lines:+,}")
    print(f"Functions:       {len(functions) - len(duplicates)}")
    print(f"Duplicates removed: {len(duplicates)}")
    print()

# ==============================================================================
# ENTRY POINT
# ==============================================================================

def main():
    """Main entry point"""

    # Set paths
    script_dir = Path(__file__).parent
    input_file = script_dir / "build.func"

    # Create backup first
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = script_dir / f"build.func.backup-{timestamp}"

    if not input_file.exists():
        print(f"❌ Error: {input_file} not found!")
        sys.exit(1)

    print(f"📦 Creating backup: {backup_file.name}")
    backup_file.write_text(input_file.read_text(encoding='utf-8'), encoding='utf-8')
    print()

    # Optimize
    output_file = script_dir / "build.func.optimized"
    optimize_build_func(input_file, output_file)

    print("📋 Next steps:")
    print(f"   1. Review: {output_file.name}")
    print(f"   2. Test the optimized version")
    print(f"   3. If OK: mv build.func.optimized build.func")
    print(f"   4. Backup available at: {backup_file.name}")
    print()

if __name__ == "__main__":
    main()
