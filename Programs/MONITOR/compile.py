#!/usr/bin/env python3
"""
compile.py - Assemble Altaid 8800 monitor programs (.ASM -> .HEX)

Uses asmx (multi-CPU assembler) to assemble Intel 8080 source files
and produce Intel HEX output suitable for loading via the monitor's
':' (Intel HEX load) command.

asmx outputs data records but no EOF record. This script appends the
EOF record ':00000001' (without the checksum byte FF, which the ROM's
GETHEXFILE routine does not consume — leaving it in the serial buffer
would trigger the F command at the monitor prompt).

Usage:
    python compile.py                  # assemble all .ASM files
    python compile.py HELLO.ASM        # assemble one file
    python compile.py WALK.ASM -v      # verbose (show listing)
"""

import os
import sys
import subprocess
import glob

# ── Configuration ──────────────────────────────────────────────────
# Default: find asmx on PATH.  Override in compile_local.py (gitignored).
ASMX_PATH = None
CPU_TYPE  = "8080"

try:
    from compile_local import ASMX_PATH  # noqa: F811
except ImportError:
    pass

if ASMX_PATH is None:
    import shutil
    ASMX_PATH = shutil.which("asmx") or shutil.which("asmx.exe")

# EOF record for Intel HEX (no checksum byte — see ROM quirk in README)
EOF_RECORD = ":00000001"

# ── Helpers ────────────────────────────────────────────────────────

def assemble(src_path, verbose=False):
    """Assemble a single .ASM file, return True on success."""
    base = os.path.splitext(src_path)[0]
    hex_path = base + ".HEX"
    lst_path = base + ".LST"
    name = os.path.basename(src_path)

    print(f"  Assembling {name} ...")

    # Run asmx
    cmd = [
        ASMX_PATH,
        "-C", CPU_TYPE,
        "-e", "-w",
        "-o", hex_path,
        "-l", lst_path,
        src_path,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    # asmx prints errors to stderr
    stderr = result.stderr.strip()
    stdout = result.stdout.strip()

    if result.returncode != 0 or "Error" in stderr or "Error" in stdout:
        print(f"  *** FAILED: {name} ***")
        if stderr:
            print(stderr)
        if stdout:
            print(stdout)
        return False

    # Check listing for errors
    errors_found = False
    if os.path.exists(lst_path):
        with open(lst_path, "r") as f:
            lst_lines = f.readlines()
        for line in lst_lines:
            if "*** Error" in line or "*** Warning" in line:
                print(f"  {line.rstrip()}")
                errors_found = True

    if errors_found:
        print(f"  *** FAILED: {name} (see {os.path.basename(lst_path)}) ***")
        return False

    # Read hex output, trim any trailing whitespace/empty lines
    if not os.path.exists(hex_path):
        print(f"  *** FAILED: {name} (no hex output) ***")
        return False

    with open(hex_path, "r") as f:
        hex_lines = [l.rstrip() for l in f.readlines() if l.strip()]

    # Remove any existing EOF records (asmx adds one with address/checksum)
    # EOF records have type 01 at byte positions 7-8 in the record
    hex_lines = [l for l in hex_lines if not (len(l) >= 9 and l[7:9] == "01")]

    # Append our EOF record (without checksum byte)
    hex_lines.append(EOF_RECORD)

    # Write final hex file (no trailing CRLF after EOF record —
    # extra bytes in the serial buffer cause spurious MENU> prompts)
    with open(hex_path, "wb") as f:
        f.write("\r\n".join(hex_lines).encode("ascii"))

    # Calculate total code size from hex records
    total_bytes = 0
    for line in hex_lines:
        if line.startswith(":") and not line.startswith(":00000001"):
            byte_count = int(line[1:3], 16)
            total_bytes += byte_count

    print(f"  OK: {name} -> {os.path.basename(hex_path)} ({total_bytes} bytes)")

    if verbose and os.path.exists(lst_path):
        print(f"\n  --- Listing ({os.path.basename(lst_path)}) ---")
        with open(lst_path, "r") as f:
            for line in f:
                print(f"  {line.rstrip()}")
        print()

    return True


def main():
    # Parse arguments
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    files = [a for a in sys.argv[1:] if not a.startswith("-")]

    # Determine source directory (same as this script)
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Check asmx exists
    if ASMX_PATH is None or not os.path.exists(ASMX_PATH):
        print("Error: asmx assembler not found.")
        print("Either add asmx to your PATH, or create compile_local.py with:")
        print('  ASMX_PATH = r"C:\\path\\to\\asmx.exe"')
        sys.exit(1)

    # Find source files
    if files:
        src_files = []
        for f in files:
            path = os.path.join(script_dir, f) if not os.path.isabs(f) else f
            if os.path.exists(path):
                src_files.append(path)
            else:
                print(f"Error: {f} not found")
                sys.exit(1)
    else:
        src_files = sorted(glob.glob(os.path.join(script_dir, "*.ASM")))
        if not src_files:
            print("No .ASM files found in", script_dir)
            sys.exit(1)

    print(f"Altaid 8800 Monitor Program Assembler")
    print(f"  asmx: {ASMX_PATH}")
    print(f"  CPU:  {CPU_TYPE}")
    print()

    # Assemble each file
    success = 0
    failed = 0
    for src in src_files:
        if assemble(src, verbose):
            success += 1
        else:
            failed += 1

    print()
    print(f"Done: {success} succeeded, {failed} failed")

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
