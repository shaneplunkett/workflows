#!/usr/bin/env bash
# Runs the hosts job's "Work out the diff" step from .github/workflows/hosts.yml
# against artifacts made up here, and checks its outputs and summary. Needs
# jq and yq (mikefarah's) on PATH.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$(mktemp)"
yq '.jobs.hosts.steps[] | select(.name == "Work out the diff") | .run' \
  "$root/.github/workflows/hosts.yml" > "$script"

failures=0
dir=""

# new <name>: a fresh RUNNER_TEMP with nothing downloaded.
new() {
  name="$1"
  dir="$(mktemp -d)"
}

# put <path> <json>: an artifact file, as the hosts job downloads it.
put() {
  mkdir -p "$(dirname "$dir/$1")"
  printf '%s\n' "$2" > "$dir/$1"
}

# host <name> <attempt> <drv> <changed> <build> [system]: a head job that got
# as far as uploading its evaluation.
host() {
  put "start/$1.json" "{\"$1\": $2}"
  put "head/drv/$1.json" "{\"$1\": \"$3\"}"
  put "head/plan/$1.json" \
    "{\"$1\": {\"system\": \"${6:-x86_64-linux}\", \"changed\": $4, \"build\": $5, \"attempt\": $2}}"
}

# built <name> <attempt>: a head job that built and pushed.
built() {
  put "built/$1.json" "{\"$1\": {\"out\": \"/nix/store/$1-out\", \"attempt\": $2}}"
}

# run [VAR=value...]: runs the step, with these defaults overridden.
run() {
  : > "$dir.out"
  : > "$dir.summary"
  (cd "$dir" && env RUNNER_TEMP="$dir" GITHUB_OUTPUT="$dir.out" GITHUB_STEP_SUMMARY="$dir.summary" \
    GITHUB_SERVER_URL=https://github.com GITHUB_REPOSITORY=owner/repo \
    LIST=success EVALUATE=success EVALUATE_BASE=skipped HOSTS='[]' BASE=base000 BASE_RUN=9 BASE_HOSTS= \
    BUILD=true EVENT=pull_request HEAD=head000 "$@" bash -eo pipefail "$script") > "$dir.log" 2>&1 ||
    { echo "FAIL $name: the step exited $?"; cat "$dir.log"; failures=$((failures + 1)); }
}

output() { grep -E "^$1=$2$" "$dir.out" > /dev/null || { echo "FAIL $name: wanted $1=$2, got $(tr '\n' ' ' < "$dir.out")"; failures=$((failures + 1)); }; }
says() { grep -F -- "$1" "$dir.summary" > /dev/null || { echo "FAIL $name: summary lacks \"$1\""; cat "$dir.summary"; failures=$((failures + 1)); }; }
lacks() { if grep -F -- "$1" "$dir.summary" > /dev/null; then echo "FAIL $name: summary has \"$1\""; cat "$dir.summary"; failures=$((failures + 1)); fi; }

new "one host builds"
host a 1 a2 true true
built a 1
put baseline/hosts.json '{"a": "a1"}'
run HOSTS='["a"]'
output ok true
output complete true
says "**1 host changes:** \`a\`"
says "Built and pushed to the cache: \`a\`"

new "no host changes, base evaluated in this run"
host a 1 a1 false false
put baseline/drv/a.json '{"a": "a1"}'
run HOSTS='["a"]' BASE_RUN= BASE_HOSTS='["a"]' EVALUATE_BASE=success
output ok true
says "**No hosts change.**"

new "a build fails, a Mac isn't built, a host is removed"
host a 1 a2 true true
host b 1 b2 true true
host mac 1 m2 true false aarch64-darwin
built a 1
put baseline/hosts.json '{"a": "a1", "b": "b1", "mac": "m1", "gone": "g1"}'
run HOSTS='["a","b","mac"]' EVALUATE=failure
output ok false
output complete true
says "**3 hosts change:**"
says "Removed: \`gone\`"
says "**Failed to build or push:** \`b\`"
says "Not built here: \`mac\` (aarch64-darwin)"

new "a host doesn't evaluate at the head"
host a 1 a1 false false
put start/b.json '{"b": 1}'
put baseline/hosts.json '{"a": "a1", "b": "b1"}'
run HOSTS='["a","b"]' EVALUATE=failure
output ok false
output complete false
says "**Incomplete diff.**"
says "\`b\` at the head"
says "None of the hosts that did evaluate change."
lacks "**No hosts change.**"

new "a host doesn't evaluate at the baseline"
host a 1 a2 true false
host b 1 b2 true false
put baseline/drv/a.json '{"a": "a1"}'
run HOSTS='["a","b"]' BASE_RUN= BASE_HOSTS='["a","b"]' EVALUATE_BASE=failure BUILD=false
output ok false
output complete false
says "\`b\` at the baseline"
says "Of the hosts that did evaluate, 1 changes: \`a\`"
lacks "\`a\`, \`b\`"

new "a rerun's baseline fails, leaving the first attempt's record"
host a 1 a1 false false
put baseline/drv/a.json '{"a": "a1"}'
run HOSTS='["a"]' BASE_RUN= BASE_HOSTS='["a"]' EVALUATE_BASE=failure
output ok false
output complete false
says "**Incomplete diff.** The baseline's evaluation failed"
lacks "**No hosts change.**"

new "a rerun fails to build, leaving the first attempt's build"
host a 2 a2 true true
built a 1
put baseline/hosts.json '{"a": "a1"}'
run HOSTS='["a"]' EVALUATE=failure
output ok false
says "**Failed to build or push:** \`a\`"
lacks "Built and pushed to the cache: \`a\`"

new "a rerun fails to evaluate, leaving the first attempt's evaluation"
host a 1 a2 true true
put start/a.json '{"a": 2}'
built a 1
put baseline/hosts.json '{"a": "a1"}'
run HOSTS='["a"]' EVALUATE=failure
output ok false
output complete false
says "\`a\` at the head"
lacks "Built and pushed"

new "re-run failed jobs keeps the hosts that weren't rerun"
host a 1 a2 true true
built a 1
host b 2 b2 true true
built b 2
put baseline/hosts.json '{"a": "a1", "b": "b1"}'
run HOSTS='["a","b"]'
output ok true
says "Built and pushed to the cache: \`a\`, \`b\`"

new "the host list doesn't evaluate"
run LIST=failure HOSTS= EVALUATE=skipped
output ok false
says "The host list didn't evaluate"

new "a push with no baseline"
host a 1 a2 true true
built a 1
run HOSTS='["a"]' BASE= BASE_RUN= EVENT=push
output ok true
says "**1 host changes:** \`a\`"
says "There's no baseline"

if [ "$failures" -gt 0 ]; then
  echo "$failures checks failed."
  exit 1
fi
echo "Every check passed."
