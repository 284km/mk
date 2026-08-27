#!/bin/sh
# verify.sh -- mk against the world it acts on.
#
# WHAT THE ORACLE IS, SAID PLAINLY. There is no second implementation of this
# dialect. `mkfile` is not a Makefile -- the recipe is on the same line as the
# name, dependencies are `[a b c]`, parallel is `&`, incremental is
# `(out: in)` -- so `make` cannot answer for it, and comparing mk to a
# recording of its own past output would catch a change and never a mistake.
#
# What it CAN be held to is the effect it has: which files exist afterwards,
# in what order things happened, and what exit code came back. Those are facts
# about the world, produced by a real shell running real commands, and they are
# what mk exists to cause. Each check below asserts one.
#
# CONCURRENCY IS CHECKED STRUCTURALLY, NOT BY A CLOCK. A parallel group of
# three tasks that each record "start" and "end" must produce all three starts
# before any end. That is a property of the schedule rather than a threshold on
# a stopwatch, so it does not become flaky on a loaded machine -- and it fails
# for the right reason if the group silently runs sequentially, which a timing
# margin generous enough to be reliable would let through.
#
#   MERE=/path/to/mere sh verify.sh
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
MERE="${MERE:-mere}"
CC="${CC:-clang}"
command -v "$MERE" >/dev/null 2>&1 || { echo "verify: no mere -- set MERE=/path/to/mere.exe" >&2; exit 1; }
command -v "$CC"   >/dev/null 2>&1 || { echo "verify: no C compiler -- set CC" >&2; exit 1; }

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
"$MERE" -c "$ROOT/main.mere" > "$BUILD/mk.c" 2>"$BUILD/emit.err" \
  || { echo "verify: mere -c failed"; sed -n '1,3p' "$BUILD/emit.err"; exit 1; }
"$CC" -O2 -w "$BUILD/mk.c" -o "$BUILD/mk" 2>"$BUILD/cc.err" \
  || { echo "verify: the emitted C did not compile"; sed -n '1,3p' "$BUILD/cc.err"; exit 1; }
MK="$BUILD/mk"

pass=0; fail=0
ok()   { pass=$((pass + 1)); printf '  ok    %-16s %s\n' "$1" "$2"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %-16s %s\n' "$1" "$2"; }

# Each case runs in its own directory: mk reads ./mkfile, and a shared one
# would let an earlier case's output file decide a later case's answer.
newdir() { d="$(mktemp -d)"; echo "$d"; }

# --- M0 / M2: a task runs, its code comes back, an unknown name does not ----
d=$(newdir); ( cd "$d" && printf 'hello: sh -c "echo hi > out"\n' > mkfile && "$MK" hello >/dev/null 2>&1 )
[ "$(cat "$d/out" 2>/dev/null)" = "hi" ] && ok task "the command ran and wrote its file" \
                                         || bad task "the command did not run"
rm -rf "$d"

d=$(newdir); ( cd "$d" && printf 'boom: exit 9\n' > mkfile && "$MK" boom >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 9 ] && ok exit-code "a failing task exits 9, not 0 or 1" \
                || bad exit-code "expected 9, got $rc"
rm -rf "$d"

d=$(newdir); ( cd "$d" && printf 'hello: true\n' > mkfile && "$MK" hello >/dev/null 2>&1 ); rc=$?
[ "$rc" -eq 0 ] && ok exit-zero "a succeeding task exits 0" \
                || bad exit-zero "expected 0, got $rc"
rm -rf "$d"

# Both halves: a program that always failed would pass the check above alone.
d=$(newdir); err=$( cd "$d" && printf 'hello: true\n' > mkfile && "$MK" nope 2>&1 >/dev/null ); rc=$?
case "$err" in
  *"no such task"*) [ "$rc" -ne 0 ] && ok unknown-task "named on stderr, nonzero exit" \
                                    || bad unknown-task "said so and still exited 0" ;;
  *) bad unknown-task "no diagnosis: [$err]" ;;
esac
rm -rf "$d"

# --- M3: dependencies run before the parent, in order -----------------------
d=$(newdir)
( cd "$d" && cat > mkfile <<'MK'
a: sh -c 'printf "start-a\n" >> log; sleep 0.2; printf "end-a\n" >> log'
b: sh -c 'printf "start-b\n" >> log; sleep 0.2; printf "end-b\n" >> log'
c: sh -c 'printf "start-c\n" >> log; sleep 0.2; printf "end-c\n" >> log'
seq [a b c]: sh -c 'printf "parent\n" >> log'
MK
"$MK" seq >/dev/null 2>&1 )
got=$(tr '\n' ' ' < "$d/log" 2>/dev/null | sed 's/ $//')
want="start-a end-a start-b end-b start-c end-c parent"
[ "$got" = "$want" ] && ok deps-order "each dep finished before the next began" \
                     || bad deps-order "got [$got]"
rm -rf "$d"

# --- M5: a parallel group actually overlaps --------------------------------
d=$(newdir)
( cd "$d" && cat > mkfile <<'MK'
a: sh -c 'printf "start-a\n" >> log; sleep 0.3; printf "end-a\n" >> log'
b: sh -c 'printf "start-b\n" >> log; sleep 0.3; printf "end-b\n" >> log'
c: sh -c 'printf "start-c\n" >> log; sleep 0.3; printf "end-c\n" >> log'
par [a b c]&: sh -c 'printf "parent\n" >> log'
MK
"$MK" par >/dev/null 2>&1 )
# The structural property: every start precedes every end.
last_start=$(grep -n '^start-' "$d/log" 2>/dev/null | tail -1 | cut -d: -f1)
first_end=$(grep -n '^end-' "$d/log" 2>/dev/null | head -1 | cut -d: -f1)
starts=$(grep -c '^start-' "$d/log" 2>/dev/null || echo 0)
if [ "$starts" -ne 3 ]; then
  bad parallel "expected 3 starts, saw $starts -- [$(tr '\n' ' ' < "$d/log" 2>/dev/null)]"
elif [ -n "$last_start" ] && [ -n "$first_end" ] && [ "$last_start" -lt "$first_end" ]; then
  ok parallel "all three started before any finished"
else
  bad parallel "ran sequentially -- [$(tr '\n' ' ' < "$d/log" 2>/dev/null)]"
fi
rm -rf "$d"

# --- M4: incremental -- build, skip, rebuild -------------------------------
d=$(newdir)
( cd "$d" && printf 'build (out.txt: in.txt): sh -c "printf ran >> ran; cp in.txt out.txt"\n' > mkfile \
  && printf 'v1\n' > in.txt && "$MK" build >/dev/null 2>&1 )
r1=$(wc -c < "$d/ran" 2>/dev/null || echo 0)
( cd "$d" && "$MK" build >/dev/null 2>&1 )
r2=$(wc -c < "$d/ran" 2>/dev/null || echo 0)
sleep 1
( cd "$d" && touch in.txt && "$MK" build >/dev/null 2>&1 )
r3=$(wc -c < "$d/ran" 2>/dev/null || echo 0)
if [ "$r1" -gt 0 ] && [ "$r2" -eq "$r1" ] && [ "$r3" -gt "$r2" ]; then
  ok incremental "built, skipped while fresh, rebuilt after the input moved"
else
  bad incremental "ran-bytes were $r1 then $r2 then $r3"
fi
rm -rf "$d"

# --- a failing dep stops the parent, in both kinds of group -----------------
for kind in '' '&'; do
  label=$([ -z "$kind" ] && echo dep-fail-seq || echo dep-fail-par)
  d=$(newdir)
  ( cd "$d" && cat > mkfile <<MK
ok1: sh -c 'printf "ok1\n" >> log'
boom: sh -c 'printf "boom\n" >> log; exit 9'
group [ok1 boom]$kind: sh -c 'printf "parent-ran\n" >> log'
MK
  "$MK" group >/dev/null 2>&1 ); rc=$?
  if grep -q parent-ran "$d/log" 2>/dev/null; then
    bad "$label" "the parent ran even though a dep failed"
  elif [ "$rc" -eq 9 ]; then
    ok "$label" "parent skipped, the dep's code came back"
  else
    bad "$label" "parent skipped but the exit code was $rc, not 9"
  fi
  rm -rf "$d"
done

echo "verify: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
