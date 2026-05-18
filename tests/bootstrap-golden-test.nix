# Golden test for bootstrap refactoring
# Verifies that the refactored modular bootstrap output produces
# byte-identical output compared to the original bootstrap.nix.
#
# This test is invoked from flake.nix as a check.
# It receives the old and new bootstrap derivations and compares every file.
{
  oldBootstrap,
  newBootstrap,
  system,
  pkgs,
}: let
  # Get list of files from the old bootstrap output
  oldFiles = builtins.readDir oldBootstrap;
  newFiles = builtins.readDir newBootstrap;

  # Check that file lists match
  fileListsMatch =
    (builtins.length (builtins.attrNames oldFiles))
    == (builtins.length (builtins.attrNames newFiles))
    && builtins.all (name: newFiles ? ${name}) (builtins.attrNames oldFiles);

  # Build comparison script
  compareScript = ''
    set -euo pipefail
    echo "=== Bootstrap Golden Test ==="
    echo "System: ${system}"
    echo "Old: ${oldBootstrap}"
    echo "New: ${newBootstrap}"
    echo ""

    OLD="${oldBootstrap}"
    NEW="${newBootstrap}"

    # Check file count
    OLD_COUNT=$(find "$OLD" -maxdepth 1 -type f | wc -l | tr -d ' ')
    NEW_COUNT=$(find "$NEW" -maxdepth 1 -type f | wc -l | tr -d ' ')
    echo "File count: old=$OLD_COUNT new=$NEW_COUNT"
    if [ "$OLD_COUNT" -ne "$NEW_COUNT" ]; then
      echo "FAIL: File count mismatch"
      exit 1
    fi

    # Check file names match
    MISSING=0
    for f in $(ls "$OLD"); do
      if [ ! -f "$NEW/$f" ]; then
        echo "MISSING in new: $f"
        MISSING=1
      fi
    done
    for f in $(ls "$NEW"); do
      if [ ! -f "$OLD/$f" ]; then
        echo "EXTRA in new: $f"
        MISSING=1
      fi
    done
    if [ "$MISSING" -eq 1 ]; then
      echo "FAIL: File name mismatch"
      exit 1
    fi

    # Compare each file byte-for-byte
    FAILURES=0
    for f in $(ls "$OLD"); do
      if ! cmp -s "$OLD/$f" "$NEW/$f"; then
        OLD_SIZE=$(wc -c < "$OLD/$f" | tr -d ' ')
        NEW_SIZE=$(wc -c < "$NEW/$f" | tr -d ' ')
        echo "DIFF: $f (old=$OLD_SIZE bytes, new=$NEW_SIZE bytes, diff=$((OLD_SIZE - NEW_SIZE)))"
        FAILURES=$((FAILURES + 1))
      fi
    done

    if [ "$FAILURES" -gt 0 ]; then
      echo ""
      echo "FAIL: $FAILURES file(s) differ"
      exit 1
    fi

    echo ""
    echo "PASS: All $OLD_COUNT files are byte-identical!"

    # Create output for check derivation
    mkdir -p $out
    echo "PASSED" > $out/result.txt
  '';
in
  pkgs.runCommand "bootstrap-golden-test" {
    nativeBuildInputs = [pkgs.diffutils];
    meta.description = "Verify refactored bootstrap produces identical output to original";
  } compareScript
