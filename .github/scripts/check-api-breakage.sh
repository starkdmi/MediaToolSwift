#!/bin/bash
#
# Fails when `swift package diagnose-api-breaking-changes` reports a public API
# breakage that is not declared in .github/expected-api-breakages.txt.
#
# Usage: check-api-breakage.sh <baseline>
#   <baseline> is anything the SwiftPM plugin accepts: a tag, a branch or a SHA.

set -uo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $(basename "$0") <baseline>" >&2
    exit 2
fi

baseline="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
allowlist="$repo_root/.github/expected-api-breakages.txt"

if [[ ! -f "$allowlist" ]]; then
    echo "missing allowlist: $allowlist" >&2
    exit 2
fi

log="$(mktemp)"
declared="$(mktemp)"
trap 'rm -f "$log" "$declared"' EXIT

swift package diagnose-api-breaking-changes "$baseline" --products MediaToolSwift 2>&1 | tee "$log"
diagnose_status="${PIPESTATUS[0]}"

# SwiftPM exits nonzero when it finds a source-breaking API change. Treat any
# other failure (for example, a failed build) as a gate failure.
if [[ "$diagnose_status" -ne 0 ]] && ! grep -Fq "API breakage:" "$log"; then
    exit "$diagnose_status"
fi

grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$allowlist" > "$declared"

# With an empty allowlist `grep -Fxv -f` passes every breakage through, so an
# emptied file fails loudly rather than silently disabling the gate.
unexpected="$(
    grep -F "API breakage:" "$log" |
        sed -e 's/^.*API breakage: //' |
        grep -Fxv -f "$declared"
)"

if [[ -n "$unexpected" ]]; then
    echo
    echo "Undeclared API breakage against ${baseline}:"
    echo "$unexpected"
    echo
    echo "If these are intentional, add each line verbatim to" \
         ".github/expected-api-breakages.txt in the commit that breaks the API."
    exit 1
fi

echo "No undeclared API breakage against ${baseline}."
