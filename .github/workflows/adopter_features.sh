#!/usr/bin/env bash
# The suite's newer commands against an adopter's canary run: compare with
# expected results, the AI analysis input (and a small local model's reading
# of it), and the evidence bundle. Writes a Markdown report; exits 1 when a
# check fails.
#
# Usage: adopter_features.sh CANARY_RESULTS BASELINE_RESULTS|"" NAME OUT_DIR [ENDPOINT MODEL]
set -uo pipefail
canary=$1 baseline=$2 name=$3 out=$4 endpoint=${5:-} model=${6:-}
mkdir -p "$out"
report="$out/features.md"
fail=0
ok() { echo "- ✅ $*" >> "$report"; }
bad() { echo "- ❌ $*" >> "$report"; fail=1; }
info() { echo "- $*" >> "$report"; }
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
cmp_json() { cnti-testsuite compare --results-file "$canary" --expected "$1" --output json 2> "$out/compare.err"; }
list() { yq -p json -r "$1 | join(\",\")" "$2"; }

{
  echo "### $name: the newer commands"
  echo
  echo "Run: $(yq -r .testsuite_version "$canary"), $(yq -r '.summary.passed' "$canary")/$(yq -r '.summary.total' "$canary") passed;" \
    "not passing: $(yq -r '[.items[] | select(.status != "passed") | .name + " (" + .status + ")"] | join(", ")' "$canary")"
  echo
  echo "#### compare"
} > "$report"

# The adopter lists what this run did not pass: nothing differs.
yq '[.items[] | select(.status != "passed") | {"test": .name, "status": .status, "reason": "not passing in the canary run"}]' "$canary" > "$out/expected.yaml"
cmp_json "$out/expected.yaml" > "$out/self.json" || bad "compare refused its own run's expectations: $(tail -2 "$out/compare.err")"
check "the run's own non-passing tests as expected: no change ($(list .changed "$out/self.json"))" test -z "$(list .changed "$out/self.json")"

failed1=$(yq -r '[.items[] | select(.status == "failed")][0].name // ""' "$canary")
if [[ -n "$failed1" ]]; then
  yq "del(.[] | select(.test == \"$failed1\"))" "$out/expected.yaml" > "$out/expected-drop.yaml"
  cmp_json "$out/expected-drop.yaml" > "$out/drop.json"
  check "$failed1 left out of the file: a regression ($(list .regressions "$out/drop.json"))" test "$(list .regressions "$out/drop.json")" = "$failed1"
else
  info "no failed test: the regression check is not run"
fi
passed1=$(yq -r '[.items[] | select(.status == "passed")][0].name // ""' "$canary")
yq ". + [{\"test\": \"$passed1\", \"status\": \"failed\", \"reason\": \"listed to make an improvement\"}]" "$out/expected.yaml" > "$out/expected-imp.yaml"
cmp_json "$out/expected-imp.yaml" > "$out/imp.json"
check "$passed1 listed as failing: an improvement ($(list .improvements "$out/imp.json"))" test "$(list .improvements "$out/imp.json")" = "$passed1"

# The adopter wrote its file from its own last run, then took this suite.
if [[ -f "$baseline" ]]; then
  yq '[.items[] | select(.status != "passed") | {"test": .name, "status": .status, "reason": "not passing in the adopter run"}]' "$baseline" > "$out/expected-baseline.yaml"
  cmp_json "$out/expected-baseline.yaml" > "$out/baseline.json"
  r=$(list .regressions "$out/baseline.json")
  check "expectations from the adopter's own run ($(yq -r .testsuite_version "$baseline")): no regression${r:+ ($r)}; changed: $(list .changed "$out/baseline.json")" test -z "$r"
  cnti-testsuite compare --results-file "$canary" --expected "$out/expected-baseline.yaml" > "$out/baseline.md" 2> /dev/null || true
fi

echo >> "$report"; echo "#### analyze" >> "$report"
nfail=$(yq -r '[.items[] | select(.status == "failed" or .status == "error")] | length' "$canary")
for level in facts logs; do
  d="$out/analysis-$level"
  if cnti-testsuite analyze prepare --provider openai-compatible --endpoint "${endpoint:-http://127.0.0.1:11434/v1}" --model "${model:-m}" \
      --dir "$d" --results-file "$canary" --include "$level" > "$d.log" 2>&1; then
    if [[ "$nfail" -gt 0 ]]; then
      check "$level: a request for the $nfail failed or errored test(s), $(wc -c < "$d/request.json") bytes; $(grep -c '^note' "$d.log") note(s)$(grep '^note' "$d.log" | sed 's/^note: /: /' | head -3 | tr '\n' ' ')" test -s "$d/request.json"
    else
      check "$level: nothing failed, nothing to send" test ! -e "$d/request.json"
    fi
  else
    bad "$level: analyze prepare refused: $(grep -v '^\[' "$d.log" | tail -2 | tr '\n' ' ')"
  fi
done
if [[ "$nfail" -gt 0 ]]; then
  d="$out/analysis-expected"
  cnti-testsuite analyze prepare --provider openai-compatible --endpoint http://127.0.0.1:11434/v1 --model m --dir "$d" \
    --results-file "$canary" --expected "$out/expected.yaml" > "$d.log" 2>&1
  check "with every failure expected: nothing sent" test ! -e "$d/request.json"
fi

# A small model's reading of the facts: well-formed, or the warning for an
# answer off the schema; an unreachable server is a failure.
d="$out/analysis-facts"
if [[ -n "$endpoint" && -f "$d/request.json" ]]; then
  # shellcheck source=/dev/null
  source "$d/request.env"
  start=$(date +%s)
  status=$(curl -sS --max-time 900 -o "$d/response.json" -w '%{http_code}' -H @"$d/request.headers" --data-binary @"$d/request.json" "$URL" 2> "$d/curl.err") || status=""
  if [[ "$status" == 400 && -f "$d/request.retry.json" ]]; then
    status=$(curl -sS --max-time 900 -o "$d/response.json" -w '%{http_code}' -H @"$d/request.headers" --data-binary @"$d/request.retry.json" "$URL" 2> "$d/curl.err") || status=""
  fi
  secs=$(( $(date +%s) - start ))
  if [[ -z "$status" ]]; then
    bad "$model did not answer: $(head -c 200 "$d/curl.err")"
  else
    cnti-testsuite analyze render --dir "$d" --response "$d/response.json" --http-status "$status" > "$d/render.log" 2>&1 || true
    if [[ -s "$d/analysis.md" ]] && grep -q '^### AI analysis (advisory' "$d/analysis.md"; then
      ok "$model answered in ${secs}s (HTTP $status): a well-formed analysis, $(grep -c '^\*\*' "$d/analysis.md") test(s) read; $(grep -o 'cited fact(s) not in the facts[^.]*' "$d/analysis.md" | head -1)"
    elif grep -q "not the expected JSON" "$d/render.log"; then
      ok "$model answered in ${secs}s (HTTP $status) off the schema: handled as a warning"
    else
      bad "$model: HTTP $status, $(grep '^warning' "$d/render.log" | head -2 | tr '\n' ' ')"
    fi
  fi
fi

echo >> "$report"; echo "#### evidence" >> "$report"
e="$out/evidence"
if cnti-testsuite evidence --results-file "$canary" --output-dir "$e" > "$e.log" 2>&1; then
  s="$e/cnti-evidence.json"
  rf=$(ls "$e"/cnti-testsuite-results-*.yml 2> /dev/null | head -1)
  check "the bundle: $(ls "$e" | tr '\n' ' ')" test -f "$s" -a -f "$e/cnti-badge.svg" -a -f "$e/cnti-badge.json" -a -n "$rf"
  check "the statement's version, status and essential count are the run's ($(yq -p json -r '.predicate.cnti | .testsuite_version + ", " + .status + ", " + (.essential_passed|tostring) + "/" + (.essential_max_passed|tostring)' "$s"))" \
    test "$(yq -p json -r '.predicate.cnti | .testsuite_version + " " + (.essential_passed|tostring) + "/" + (.essential_max_passed|tostring)' "$s")" = \
         "$(yq -r '.testsuite_version + " " + (.summary.essential_passed|tostring) + "/" + (.summary.essential_max_passed|tostring)' "$canary")"
  check "the badge reads $(yq -p json -r '.label + " " + .message' "$e/cnti-badge.json")" \
    test "$(yq -p json -r '.label + " " + .message' "$e/cnti-badge.json")" = "CNTi essential $(yq -r '(.summary.essential_passed|tostring) + "/" + (.summary.essential_max_passed|tostring)' "$canary")"
  check "the bundled results file has the platform block ($(yq -r '.platform | keys | join(", ")' "$rf" 2>/dev/null))" test "$(yq -r '.platform.nodes // "" | length' "$rf")" -gt 0
  info "the statement has a platform field: $(yq -p json -r '.predicate.cnti | has("platform")' "$s")"
else
  bad "evidence refused: $(grep -v '^\[' "$e.log" | tail -2 | tr '\n' ' ')"
fi
exit $fail
