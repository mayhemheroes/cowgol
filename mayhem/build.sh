#!/usr/bin/env bash
# cowgol/mayhem/build.sh — build the cowgol FRONT END (cowfe-for-80386-with-nncgen) as the fuzz
# target, plus a clean normal-flags build of the same binary for cowgol's own front-end test suite
# (mayhem/test.sh).
#
# cowgol is a self-hosting, bootstrapped compiler for the Ada-inspired Cowgol language, built with
# the `ab` build system (a Python frontend that generates ninja, driven via `make <target>`). The
# Mayhem target is the FRONT END for the 80386/nncgen toolchain: it lexes+PARSES a .cow source
# (lexer, lemon-generated parser, namespace/symbol/type/expression analysis) and emits binary midcode
# (.cob). That binary is itself produced by a C-backend bootstrap chain:
#     bootstrap C sources (cowfe/cowbe/cowlink, prebuilt, in bootstrap/*.bootstrap.c)
#       -> ncgen toolchain  -> cgen-targeted cowfe/cowbe/cowlink (compiler written in Cowgol, emitted to C)
#       -> nncgen toolchain -> cowfe-for-80386-with-nncgen  (the front end we fuzz)
# Every stage is plain C compiled by $CC — no exotic cross toolchain needed for THIS target (the
# 80386/Z80/etc. *runtime* targets would need binutils/qemu/nasm, but the front-end binary does not).
#
# WHY NOT just `make CC=clang CFLAGS=$SANITIZER_FLAGS`: the ab build uses ONE compiler/flag set for
# everything, including the HOST build tools (lemon parser generator, newgen, the bootstrap cowfe/cowbe)
# that must RUN during the build. Compiling those with ASan+UBSan breaks the build two ways:
#   * lemon.c trips UBSan's `function` check (a benign function-pointer-cast in its qsort comparators)
#     and halts -> build stops; and
#   * the bootstrap cowfe (which never frees, by design) makes LeakSanitizer abort at exit while it's
#     compiling the cgen toolchain -> build stops.
# So we build the WHOLE tree with NORMAL flags (clean, no sanitizer) so all host/bootstrap tools run,
# then RELINK only the final target's generated C — cowfe-for-80386-with-nncgen.c, which IS the
# front-end fuzz surface — WITH $SANITIZER_FLAGS. That yields a fully instrumented fuzz target without
# sanitizing the build tools.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty value
# (--build-arg SANITIZER_FLAGS=) is honored -> no-sanitizer build (the compiler's natural crash). The
# front end links no external libs, so the empty-sanitizer relink links cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
# DWARF <= 3 debug info on the fuzz target (§6.2 item 10): Mayhem's triage can't read DWARF >= 4, and
# clang-19's plain `-g` emits DWARF-5. The base image may export DEBUG_FLAGS; default to -g -gdwarf-3.
# Threaded LAST into the fuzz relink so its -gdwarf-3 wins over the -g already in SANITIZER_FLAGS.
: "${DEBUG_FLAGS=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS

cd "$SRC"

TARGET=cowfe-for-80386-with-nncgen
ABTARGET="bin/$TARGET"

# ---------------------------------------------------------------------------
# (1) NORMAL-flags build of the whole front-end chain. clang as both CC and HOSTCC (no sanitizer); -w
#     silences upstream's clean-build warnings (they don't affect codegen). This produces:
#       * all host/bootstrap tools (they run cleanly), and
#       * bin/cowfe-for-80386-with-nncgen — the honest, un-sanitized TEST ORACLE for mayhem/test.sh.
# ---------------------------------------------------------------------------
make clean >/dev/null 2>&1 || true
rm -rf .obj bin
make -j"$MAYHEM_JOBS" \
     CC="$CC" CXX="$CXX" HOSTCC="$CC" HOSTCXX="$CXX" \
     CFLAGS="-O2 -g -w" CXXFLAGS="-O2 -g -w" HOSTCFLAGS="-O2 -g -w" HOSTCXXFLAGS="-O2 -g -w" \
     "$ABTARGET"

mkdir -p "$SRC/build-tests"
cp -f "$ABTARGET" "$SRC/build-tests/$TARGET"   # normal-flags oracle for test.sh

# ---------------------------------------------------------------------------
# (2) FUZZ target — relink ONLY the final generated C (the front-end source) WITH $SANITIZER_FLAGS so
#     the fuzzed code is instrumented (ASan+UBSan, halting, by default). The generated C #includes
#     "cowgol.h" from rt/cgen, and needs no other source/lib.
#
#     LeakSanitizer OFF for this target: cowfe is a short-lived compiler that allocates from an arena
#     it never frees (arena-by-exit), so LSan (run at exit, part of ASan) reports benign "leaks" on
#     essentially every non-trivial input — which would flood the fuzzer with spurious crashes. We
#     disable ONLY leak detection (keeping ASan's heap/stack/global overflow + use-after-free checks
#     and all of UBSan, still halting), baked into the binary via a weak __asan_default_options so it
#     holds however the binary is launched (fuzzer / standalone repro / smoke test), not only when
#     ASAN_OPTIONS is set. (Cohort precedent: cproc bakes the same override; espeak-ng/flac/frr export
#     it. We also set ASAN_OPTIONS=detect_leaks=0 in mayhem/Mayhemfile_cowfe-80386 for documentation.)
# ---------------------------------------------------------------------------
GENC="$(find .obj -name "$TARGET.c" -print -quit)"
[ -n "$GENC" ] && [ -f "$GENC" ] || { echo "build.sh: could not find generated $TARGET.c under .obj" >&2; exit 1; }

ASAN_OPTS_SRC=""
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  cat > /tmp/cowgol_asan_opts.c <<'EOF'
/* Disable LeakSanitizer for cowfe: cowgol's front end never frees by design (arena-by-exit), so LSan
   would report benign leaks on nearly every input. Keeps the rest of ASan + UBSan active and halting. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
EOF
  ASAN_OPTS_SRC=/tmp/cowgol_asan_opts.c
fi

# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -O1 -w -I "$SRC/rt/cgen" "$GENC" $ASAN_OPTS_SRC -o /mayhem/"$TARGET"

echo "build.sh: built /mayhem/$TARGET (sanitized fuzz target) and build-tests/$TARGET (test oracle)"
ls -l /mayhem/"$TARGET" "$SRC/build-tests/$TARGET"
