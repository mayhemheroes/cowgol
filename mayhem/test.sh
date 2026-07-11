#!/usr/bin/env bash
# cowgol/mayhem/test.sh — front-end KNOWN-ANSWER oracle. RUNS the normal-flags cowfe
# (cowfe-for-80386-with-nncgen) that mayhem/build.sh produced against a curated set of inputs and
# asserts the front end's OBSERVABLE behavior: valid .cow sources compile to a midcode (.cob) of the
# EXACT expected byte size; malformed sources are REJECTED with the EXACT expected diagnostic.
#
# This is anti-reward-hacking by construction:
#   * The valid-program cases assert the produced .cob's exact size. A no-op / exit(0) "patch" (or any
#     change that stops the front end emitting real midcode) yields an empty or wrong-sized .cob and
#     FAILS — "ran without crashing" is NOT enough.
#   * The malformed cases assert the exact `error:` text. A patch that makes everything succeed (to
#     dodge a crash) stops emitting these diagnostics and FAILS.
# The sizes/messages are deterministic for this binary (verified stable across runs); they exercise the
# lexer, the lemon parser, namespace/symbol resolution, type and expression analysis — the fuzzed code.
#
# Does NOT compile — mayhem/build.sh already built the oracle binary (build-tests/<target>, normal
# flags). If it's missing, that's a build.sh bug — fail loudly.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/build-tests/cowfe-for-80386-with-nncgen"
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; exit 2; }

# Include search path so sources that `include` the cowgol runtime headers resolve:
#   cowgol.coh -> rt/cgen/ ; common.coh -> rt/ ; tests/_framework.coh -> . (repo root)
INC=(-Irt/cgen/ -Irt/ -I.)
OUT="$(mktemp -d)"
PASS=0; FAIL=0

# ---- VALID programs: must compile (exit 0) AND emit a .cob of the EXACT expected size ----
# "<source>|<expected .cob bytes>"
VALID=(
  "examples/empty.cow|4106"
  "examples/helloworld.cow|4145"
  "examples/icando.cow|4404"
  "examples/argv.cow|4736"
  "examples/mandel.cow|5068"
  "examples/file.cow|11120"
  "examples/filetester.cow|10906"
  "tests/atoi.test.cow|5253"
  "tests/case.test.cow|14381"
  "tests/casts.test.cow|10880"
  "tests/conditionals.test.cow|12635"
  "tests/addsub-8bit.test.cow|7777"
  "tests/addsub-16bit.test.cow|9128"
  "tests/addsub-32bit.test.cow|8909"
  "tests/arrayinitialisers.test.cow|5686"
)
for entry in "${VALID[@]}"; do
  src="${entry%%|*}"; want="${entry##*|}"
  cob="$OUT/$(echo "$src" | tr / _).cob"
  if "$BIN" "${INC[@]}" "$src" "$cob" >/dev/null 2>&1; then
    got="$(stat -c%s "$cob" 2>/dev/null || echo -1)"
    if [ "$got" = "$want" ]; then
      PASS=$((PASS+1))
    else
      FAIL=$((FAIL+1)); echo "FAIL valid $src: .cob size $got, expected $want" >&2
    fi
  else
    FAIL=$((FAIL+1)); echo "FAIL valid $src: front end returned non-zero (expected success)" >&2
  fi
done

# ---- MALFORMED inputs: must be REJECTED (exit non-zero) AND print the EXACT diagnostic ----
reject_case() {
  local src="$1" want="$2" f="$OUT/bad.cow" out rc
  printf '%s' "$src" > "$f"
  out="$("$BIN" "${INC[@]}" "$f" "$OUT/bad.cob" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    FAIL=$((FAIL+1)); echo "FAIL reject [$src]: accepted (expected rejection)" >&2; return
  fi
  if printf '%s' "$out" | grep -qF "$want"; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL reject [$src]: missing diagnostic '$want' (got: $(printf '%s' "$out" | grep -m1 error: || echo none))" >&2
  fi
}
reject_case 'var x := @bad;'  "symbol '@bad' not found"
reject_case 'sub foo is'      'unexpected IS'
reject_case '@#$%^&*'         "symbol '@' not found"

rm -rf "$OUT"
emit_ctrf "cowgol-cowfe-known-answer" "$PASS" "$FAIL"
