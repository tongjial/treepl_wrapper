#!/usr/bin/env bash
#
# treepl_wrapper.sh - run the treePL prime -> cross-validation -> smoothing
# pipeline in a single command.
#
# version: 1.0
#
# Usage: treepl_wrapper.sh [options] configuration treefile label
#
# Exit codes:
#   0  success
#   1  usage or environment error (bad arguments, invalid label, treePL missing)
#   2  configuration file or tree file not found
#   3  cross-validation failed (treePL error, empty or invalid cv output)
#   4  prime step failed (treePL error or optimal parameters not parsable)
#   5  smoothing step failed (treePL error or no dated tree produced)
#
# Environment variables:
#   TREEPL_BIN          treePL executable (default: treePL)
#   TREEPL_PRIME_RUNS   number of prime runs (default: 100)
#   TREEPL_CV_START     cvstart value (default: 0.0001)
#   TREEPL_CV_STOP      cvstop value (default: 10000)
#   TREEPL_KEEP_TMP     set to 1 to keep the temporary working directory
#   TMPDIR              parent directory of the temporary working directory

set -euo pipefail

readonly VERSION="1.0"
readonly PROG="${0##*/}"

TREEPL_BIN="${TREEPL_BIN:-treePL}"
PRIME_RUNS="${TREEPL_PRIME_RUNS:-100}"
CV_START="${TREEPL_CV_START:-0.0001}"
CV_STOP="${TREEPL_CV_STOP:-10000}"
KEEP_TMP="${TREEPL_KEEP_TMP:-0}"

usage() {
	cat <<USAGE
Usage: $PROG [options] configuration treefile label

Estimate a time tree with treePL in three stages:
  1. run the prime step $PRIME_RUNS times and keep the most frequent optimal parameters
  2. run cross-validation and pick the smoothing value with the smallest cv score
  3. date the tree(s) with that smoothing value

Arguments:
  configuration  treePL configuration file (numsites, mrca, min, max, nthreads, ...)
                 without treefile, prime, cv or smoothing lines
  treefile       rooted tree(s) in Newick format (best ML tree first, then bootstraps)
  label          name used for output files; must not contain '/' or '='

Options:
  -h, --help     show this help and exit
  --version      show version and exit

Outputs (in the current directory):
  treepl_<label>.tre       dated tree(s)
  treepl_<label>.tre.r8s   r8s-style tree(s), if written by treePL
  prime_<label>.log        treePL output of all prime runs
  cv_<label>.log           treePL output of the cross-validation step
  final_<label>.log        treePL output of the smoothing step

Environment variables:
  TREEPL_BIN (treePL), TREEPL_PRIME_RUNS (100), TREEPL_CV_START (0.0001),
  TREEPL_CV_STOP (10000), TREEPL_KEEP_TMP (0), TMPDIR

Exit codes:
  0 success, 1 usage/environment error, 2 input file not found,
  3 cross-validation failed, 4 prime step failed, 5 smoothing step failed
USAGE
}

error() {
	printf 'Error: %s\n' "$*" >&2
}

short_usage() {
	printf 'Usage: %s [options] configuration treefile label (see --help)\n' "$PROG" >&2
}

die() {
	local code="$1"
	shift
	error "$@"
	exit "$code"
}

banner() {
	echo "================================================================"
}

is_number() {
	[[ "$1" =~ ^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$ ]]
}

abs_path() {
	local dir
	dir="$(cd -- "$(dirname -- "$1")" && pwd -P)"
	printf '%s/%s\n' "$dir" "$(basename -- "$1")"
}

# ---------------------------------------------------------------------------
# command line
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--version)
		echo "$PROG $VERSION"
		exit 0
		;;
	--)
		shift
		break
		;;
	-?*)
		error "unknown option: $1"
		short_usage
		exit 1
		;;
	*)
		break
		;;
	esac
done

if [ $# -ne 3 ]; then
	error "incorrect usage (expected 3 arguments, got $#)"
	short_usage
	exit 1
fi

CONFIG="$1"
TREEFILE="$2"
LABEL="$3"

if [ -z "$LABEL" ] || [[ "$LABEL" == */* ]] || [[ "$LABEL" == *=* ]]; then
	die 1 "invalid label '$LABEL': must be non-empty and must not contain '/' or '='"
fi

if ! [[ "$PRIME_RUNS" =~ ^[1-9][0-9]*$ ]]; then
	die 1 "TREEPL_PRIME_RUNS must be a positive integer, got '$PRIME_RUNS'"
fi
# treePL scans smoothing values by repeated multiplication with 0.1, so a bound
# <= 0 would never be reached and cross-validation would run forever.
if ! is_number "$CV_START" || ! is_number "$CV_STOP" ||
	! awk -v a="$CV_START" -v b="$CV_STOP" 'BEGIN { exit !(a > 0 && b > 0) }'; then
	die 1 "TREEPL_CV_START and TREEPL_CV_STOP must be positive numbers, got '$CV_START' and '$CV_STOP'"
fi

if ! TREEPL_PATH="$(command -v -- "$TREEPL_BIN")"; then
	die 1 "treePL not found (TREEPL_BIN='$TREEPL_BIN'); install it or put it in PATH"
fi
# treePL runs inside the temporary directory, so a relative path must be made absolute.
if [[ "$TREEPL_PATH" == */* ]] && [[ "$TREEPL_PATH" != /* ]]; then
	TREEPL_PATH="$(abs_path "$TREEPL_PATH")"
fi

if [ ! -f "$CONFIG" ]; then
	error "can't find the configuration file: $CONFIG"
	short_usage
	exit 2
fi
if [ ! -f "$TREEFILE" ]; then
	error "can't find the tree file: $TREEFILE"
	short_usage
	exit 2
fi

TREEFILE_ABS="$(abs_path "$TREEFILE")"
if [[ "$TREEFILE_ABS" == *=* ]]; then
	die 1 "tree file path must not contain '=' (treePL splits configuration lines on '='): $TREEFILE_ABS"
fi

# ---------------------------------------------------------------------------
# temporary working directory
# ---------------------------------------------------------------------------

OUTDIR="$(pwd -P)"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/treepl_wrapper.XXXXXX")"
# Scratch files live in a subdirectory so they can never collide with the
# label-derived file names (labels cannot contain '/').
SCRATCH="$WORKDIR/scratch"
mkdir -- "$SCRATCH"

PRIME_CONF="configure_prime_$LABEL"
PRIME_OUT="prime_$LABEL"
CV_CONF="configure_cv_$LABEL"
CV_OUT="cv_$LABEL"
SMOOTH_CONF="configure_smooth_$LABEL"
RESULT="treepl_$LABEL.tre"
PRIME_LOG="prime_$LABEL.log"
CV_LOG="cv_$LABEL.log"
FINAL_LOG="final_$LABEL.log"

cleanup() {
	local rc=$?
	local log
	for log in "$PRIME_LOG" "$CV_LOG" "$FINAL_LOG"; do
		if [ -f "$WORKDIR/$log" ]; then
			cp -- "$WORKDIR/$log" "$OUTDIR/$log" || true
		fi
	done
	if [ "$KEEP_TMP" = "1" ]; then
		echo "temporary files kept in: $WORKDIR" >&2
	else
		rm -rf -- "$WORKDIR"
	fi
	exit "$rc"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_treepl() {
	(cd -- "$WORKDIR" && "$TREEPL_PATH" "$1")
}

# Reduce one prime run's output to a single line.
#
# A successful treePL prime run ends with:
#   PLACE THE LINES BELOW IN THE CONFIGURATION FILE
#   opt = 3
#   moredetail         (optional)
#   optad = 2
#   moredetailad       (optional)
#   optcvad = 5
#   moredetailcvad     (optional)
#
# Starting from the first line beginning with "opt", the last character of
# every line is kept and the characters are joined with spaces, e.g.
# "3 l 2 d 5 d" or "3 2 5". treePL option indices are single digits (0-5).
extract_prime_line() {
	sed -n '/^opt/,$p' "$1" |
		sed 's/.*\(.\)/\1/' |
		paste -s -d ' ' -
}

# Pick the most frequent prime line and turn it into treePL configuration
# lines (opt/optad/optcvad plus the selected moredetail* flags).
# Returns non-zero if the three parameters can not be extracted.
parse_prime_params() {
	local mode
	mode="$(sort -- "$1" | uniq -c | sort -nr | awk 'NR == 1')"
	[ -n "$mode" ] || return 1
	awk '
	{
		# $1 is the uniq count; the rest is: opt [l] optad [d] optcvad [d]
		i = 2
		opt = $(i++)
		md = ""; if ($i == "l") { md = "moredetail"; i++ }
		optad = $(i++)
		mdad = ""; if ($i == "d") { mdad = "moredetailad"; i++ }
		optcvad = $(i++)
		mdcv = ""; if ($i == "d") { mdcv = "moredetailcvad"; i++ }
		if (opt !~ /^[0-9]$/ || optad !~ /^[0-9]$/ || optcvad !~ /^[0-9]$/ || i <= NF)
			exit 1
		print "opt = " opt
		if (md != "") print md
		print "optad = " optad
		if (mdad != "") print mdad
		print "optcvad = " optcvad
		if (mdcv != "") print mdcv
	}' <<<"$mode"
}

# Print the smoothing value with the smallest finite cv score.
# treePL writes one line per smoothing value: "chisq: (<smoothing>) <score>".
best_smoothing() {
	awk '
	$1 == "chisq:" && $2 ~ /^\(.*\)$/ && $3 ~ /^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/ {
		if (!found || $3 + 0 < best) { best = $3 + 0; smooth = $2; found = 1 }
	}
	END {
		if (!found) exit 1
		gsub(/[()]/, "", smooth)
		print smooth
	}' "$1"
}

# ---------------------------------------------------------------------------
# pipeline
# ---------------------------------------------------------------------------

banner
date
echo "$PROG $CONFIG $TREEFILE $LABEL"
echo "start running, good luck!"
banner

echo "Step1: generate the prime configure file"

{
	printf 'treefile = %s\n' "$TREEFILE_ABS"
	awk '{ print }' <"$CONFIG"
	printf 'thorough\nprime\n'
} >"$WORKDIR/$PRIME_CONF"

echo "Step2: run primes $PRIME_RUNS times"

: >"$WORKDIR/$PRIME_OUT"
: >"$WORKDIR/$PRIME_LOG"
for ((run = 1; run <= PRIME_RUNS; run++)); do
	if ! run_treepl "$PRIME_CONF" >"$SCRATCH/prime_run.out" 2>&1; then
		cat -- "$SCRATCH/prime_run.out" >>"$WORKDIR/$PRIME_LOG"
		die 4 "treePL prime failed (run $run/$PRIME_RUNS); see $PRIME_LOG"
	fi
	{
		printf '=== prime run %d ===\n' "$run"
		cat -- "$SCRATCH/prime_run.out"
	} >>"$WORKDIR/$PRIME_LOG"
	extract_prime_line "$SCRATCH/prime_run.out" >>"$WORKDIR/$PRIME_OUT"
done

echo "Step3: generate the cv configure file"

{
	sed 's/^prime/#&/' "$WORKDIR/$PRIME_CONF"
	printf 'cv\ncvoutfile = %s\ncvstart = %s\ncvstop = %s\n' "$CV_OUT" "$CV_START" "$CV_STOP"
} >"$WORKDIR/$CV_CONF"

echo "Step4: choose the most frequent cv optimal parameters"

if ! PRIME_PARAMS="$(parse_prime_params "$WORKDIR/$PRIME_OUT")"; then
	die 4 "could not parse opt/optad/optcvad from the prime output; see $PRIME_LOG"
fi
printf '%s\n' "$PRIME_PARAMS" >>"$WORKDIR/$CV_CONF"
printf '%s\n' "$PRIME_PARAMS" | sed 's/^/    /'

echo "Step5: perform cross validation, may wait a long time"

if ! run_treepl "$CV_CONF" >"$WORKDIR/$CV_LOG" 2>&1; then
	die 3 "treePL cross-validation failed; see $CV_LOG"
fi

echo "Step6: check the cv output"

if [ ! -f "$WORKDIR/$CV_OUT" ]; then
	die 3 "cv output file was not created; see $CV_LOG"
fi
if [ ! -s "$WORKDIR/$CV_OUT" ]; then
	die 3 "cv output empty; see $CV_LOG"
fi
if ! SMOOTHING="$(best_smoothing "$WORKDIR/$CV_OUT")" || ! is_number "$SMOOTHING"; then
	die 3 "cv output contains no valid smoothing value with a finite score; see $CV_LOG"
fi

echo "Step7: generate the smooth configure file (smallest cv score: smoothing = $SMOOTHING)"

{
	sed 's/^cv/#&/' "$WORKDIR/$CV_CONF"
	printf 'outfile = %s\nsmoothing = %s\n' "$RESULT" "$SMOOTHING"
} >"$WORKDIR/$SMOOTH_CONF"

echo "Step8: the last step"

if ! run_treepl "$SMOOTH_CONF" >"$WORKDIR/$FINAL_LOG" 2>&1; then
	die 5 "treePL smoothing failed; see $FINAL_LOG"
fi
if [ ! -s "$WORKDIR/$RESULT" ]; then
	die 5 "treePL did not write $RESULT; see $FINAL_LOG"
fi

cp -- "$WORKDIR/$RESULT" "$OUTDIR/$RESULT"
if [ -f "$WORKDIR/$RESULT.r8s" ]; then
	cp -- "$WORKDIR/$RESULT.r8s" "$OUTDIR/$RESULT.r8s"
fi

banner
echo "running finished, result: $RESULT"
echo "please check the result and report the bugs"
date
banner
