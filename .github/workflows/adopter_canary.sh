#!/usr/bin/env bash
# Helpers for the adopter canary (adopter_canary.yml, #2727).
#
#   adopter_canary.sh baseline <repo> <workflow> <artifact> <dir>
#     Finds the adopter's latest completed run of <workflow> on its default
#     branch that still has the results artifact, downloads it into <dir>,
#     and prints "run_id head_sha run_url" for the GitHub output.
#
#   adopter_canary.sh baseline-gitlab <project path> <job name> <dir>
#     The same for an adopter on gitlab.com: the latest job named <job name>
#     in a pipeline of the project's default branch, child pipelines
#     included, whose artifacts still hold a results file. Public projects
#     need no token; GITLAB_TOKEN is sent when set.
#
#   adopter_canary.sh compare <baseline.yml> <canary.yml> <display name> <markdown out> [expected.json]
#     Compares the two results files test by test and writes the report as
#     Markdown. Every test whose result differs is a change; a change listed
#     in expected.json (the adopter's `expected` entries: test, from, to,
#     reason) is reported as expected. Exits 1 when a change is not listed,
#     or when the canary run ended in an error. A listed change that no
#     longer occurs is reported, so the list can be pruned.
#
# Needs gh (with GH_TOKEN), curl, unzip, yq and jq, which GitHub-hosted
# runners have.
set -euo pipefail
# sort and join must agree on the collation.
export LC_ALL=C

baseline() {
  local repo=$1 workflow=$2 artifact=$3 dir=$4
  local branch
  branch=$(gh api "repos/$repo" -q .default_branch)
  # Runs from pull requests use a read-only job and test the PR's changes,
  # not the adopter's state; only runs on the default branch count.
  gh api "repos/$repo/actions/workflows/$workflow/runs?branch=$branch&status=completed&per_page=20" \
    -q '.workflow_runs[] | select(.event != "pull_request") | "\(.id) \(.head_sha) \(.html_url)"' |
  while read -r id sha url; do
    rm -rf "$dir"
    if gh run download "$id" -R "$repo" -n "$artifact" -D "$dir" >/dev/null 2>&1 &&
       ls "$dir"/cnti-testsuite-results-*.yml >/dev/null 2>&1; then
      echo "$id $sha $url"
      return 0
    fi
  done
}

GITLAB_API=${GITLAB_API:-https://gitlab.com/api/v4}

# -L: an artifacts download is a redirect to the object store.
gitlab_get() {
  curl -sSfL ${GITLAB_TOKEN:+-H "PRIVATE-TOKEN: $GITLAB_TOKEN"} "$GITLAB_API/$1"
}

# The jobs of a pipeline and of the child pipelines it triggers, newest
# pipeline first, as "job_id job_name status artifacts_expire_at web_url".
gitlab_pipeline_jobs() {
  local project=$1 pipeline=$2
  gitlab_get "projects/$project/pipelines/$pipeline/jobs?per_page=100" |
    jq -r '.[] | "\(.id) \(.name) \(.status) \(.artifacts_expire_at // "-") \(.web_url)"'
  gitlab_get "projects/$project/pipelines/$pipeline/bridges?per_page=100" |
    jq -r '.[] | .downstream_pipeline // empty | .id' |
  while read -r child; do
    gitlab_get "projects/$project/pipelines/$child/jobs?per_page=100" |
      jq -r '.[] | "\(.id) \(.name) \(.status) \(.artifacts_expire_at // "-") \(.web_url)"'
  done
}

baseline_gitlab() {
  local path=$1 job_name=$2 dir=$3
  local project branch now
  project=$(jq -rn --arg p "$path" '$p | @uri')
  branch=$(gitlab_get "projects/$project" | jq -r .default_branch)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Pipelines of pushes to the default branch; merge request pipelines test
  # the MR's changes, not the adopter's state. A job that ran but failed
  # its objective still has its results. Process substitution, not a
  # pipeline, so the return leaves the function.
  local pipeline sha id url
  while read -r pipeline sha; do
    while read -r id _ _ _ url; do
      rm -rf "$dir"
      mkdir -p "$dir"
      if gitlab_get "projects/$project/jobs/$id/artifacts" > "$dir/artifacts.zip" 2>/dev/null &&
         unzip -q -o "$dir/artifacts.zip" -d "$dir" 'cnti/results/*' 2>/dev/null &&
         ls "$dir"/cnti/results/cnti-testsuite-results-*.yml >/dev/null 2>&1; then
        echo "$id $sha $url"
        return 0
      fi
    done < <(gitlab_pipeline_jobs "$project" "$pipeline" |
      awk -v name="$job_name" -v now="$now" '$2 == name && ($3 == "success" || $3 == "failed") && ($4 == "-" || $4 > now)')
  done < <(gitlab_get "projects/$project/pipelines?ref=$branch&source=push&per_page=20" |
    jq -r '.[] | "\(.id) \(.sha)"')
}

# The newest results file in a directory, or in its cnti/results.
newest() {
  ls -t "$1"/cnti-testsuite-results-*.yml "$1"/cnti/results/cnti-testsuite-results-*.yml 2>/dev/null | head -1
}

# name<TAB>status<TAB>message for every test in a results file.
tests_of() {
  yq -o=json '.items // []' "$1" |
    jq -r '.[] | [.name, .status, ((.message // "") | gsub("[\t\n|]"; " "))] | @tsv'
}

compare() {
  local base=$1 canary=$2 name=$3 out=$4 expected=${5:-}
  [[ -n "$expected" && -s "$expected" ]] || { expected=$(mktemp); echo '[]' > "$expected"; }
  local base_tsv canary_tsv
  base_tsv=$(mktemp)
  canary_tsv=$(mktemp)
  tests_of "$base" | sort > "$base_tsv"
  tests_of "$canary" | sort > "$canary_tsv"

  local base_version canary_status canary_exit
  base_version=$(yq '.testsuite_version' "$base")
  canary_status=$(yq '.status' "$canary")
  canary_exit=$(yq '.exit_code' "$canary")

  # One row per test whose result differs, or that only one run has ("-").
  local rows unexpected=0 seen=""
  rows=$(join -t $'\t' -a 1 -a 2 -e '-' -o '0,1.2,2.2,2.3' "$base_tsv" "$canary_tsv" |
    awk -F'\t' '$2 != $3')
  {
    echo "### $name"
    echo
    echo "Baseline: the adopter's own run with suite $base_version. Canary: this commit's suite, same chart commit and kind config."
    echo
    echo "| | Adopter's run | Canary |"
    echo "|---|---|---|"
    echo "| Status | $(yq '.status' "$base") | $canary_status |"
    echo "| Essential passed | $(yq '.summary.essential_passed // "-"' "$base") | $(yq '.summary.essential_passed // "-"' "$canary") |"
    echo
    if [[ -z "$rows" ]]; then
      echo "No test changed its result."
    else
      echo "| Test | Adopter's run | Canary | | Canary's message |"
      echo "|---|---|---|---|---|"
      while IFS=$'\t' read -r test was now message; do
        local reason verdict
        reason=$(jq -r --arg t "$test" --arg f "$was" --arg n "$now" \
          'map(select(.test == $t and .from == $f and .to == $n)) | first | .reason // empty' "$expected")
        if [[ -n "$reason" ]]; then
          verdict="expected: $reason"
          seen="$seen $test"
        else
          verdict="**unexpected**"
          unexpected=$((unexpected + 1))
        fi
        echo "| \`$test\` | $was | $now | $verdict | $message |"
      done <<< "$rows"
    fi
    echo
    # Expected changes that did not occur: the adopter has caught up, or the
    # change was reverted. The entry can go.
    local stale
    stale=$(jq -r --arg seen "$seen" '.[] | . as $e | select(($seen | split(" ") | index($e.test)) | not) | "- `\(.test)` \(.from) to \(.to): \(.reason)"' "$expected")
    if [[ -n "$stale" ]]; then
      echo "Expected changes that no longer occur (remove them from \`.github/adopters.yml\`):"
      echo
      echo "$stale"
      echo
    fi
  } > "$out"

  if [[ -n "$(jq -r --arg seen "$seen" '.[] | . as $e | select(($seen | split(" ") | index($e.test)) | not) | .test' "$expected")" ]]; then
    echo "::warning::$name: some expected changes no longer occur; see the job summary"
  fi
  if [[ "$canary_exit" == "2" ]]; then
    echo "::error::$name: the canary run ended in an error (exit code 2)"
    return 1
  fi
  if (( unexpected > 0 )); then
    echo "::error::$name: $unexpected test(s) changed their result and are not listed as expected"
    return 1
  fi
  if [[ -n "$rows" ]]; then
    echo "::notice::$name: $(wc -l <<< "$rows") test(s) changed their result, all as expected"
  fi
}

cmd=$1
shift
case "$cmd" in
  baseline) baseline "$@" ;;
  baseline-gitlab) baseline_gitlab "$@" ;;
  newest) newest "$@" ;;
  compare) compare "$@" ;;
  *) echo "unknown command: $cmd" >&2; exit 64 ;;
esac
