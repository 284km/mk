# PAIN log — mk dogfood

Friction hit building a **task runner / build tool** in Mere. Chosen to surface the biggest missing capability: **running external
programs**. Each entry is a signal for a language / runtime improvement.

Status legend: 🔴 open · 🟡 worked around · 🟢 fixed upstream

---

## P1 🔴 No way to run an external program (subprocess)

The whole point of a build tool is to invoke other programs (a compiler, a
linter, `rm`, `git`). Mere had **no builtin to start a subprocess**: `run`
is an unbound variable, and there is no `exec` / `system` / `spawn_process`
equivalent. So M0 — "run one command, get its exit code" — cannot even be
expressed.

```
let code = run "echo hi" in print (show code)
//              ^^^ type error: unbound variable: run
```

Mere had file I/O (`read_file` / `write_file`), stdin (`read_stdin`), args,
and `exit` (all added for the `mq` CLI dogfood), plus TCP / HTTP — but no
process control. A whole class of tools (build systems, task runners, dev
tooling, anything that shells out) was inexpressible.

**Signal (M0, upstream):** add a `run : str -> int` builtin — run a command
line via the shell, inherit stdio, return the exit code — to the
interpreter and the C backend (native is the target, like mq). Later:
`run_out : str -> (int * str)` to capture stdout (M1), and directory / stat
builtins for incremental builds (M4).

## P2 🟢 `print_err` missing in the C backend (fixed upstream, mere v0.1.14)

M2 (a taskfile runner) prints an error to stderr for an unknown task:
`print_err ("mk: no such task: " ++ name)`. This works in the interpreter,
but the native build fails to compile:

```
error: use of undeclared identifier 'print_err'
```

The C backend lowers `print` to `puts(...)` but has no `print_err` case, so
a native CLI can't write to stderr — awkward for a tool that must separate
diagnostics from output. Same family as mq's `str_eq` / `join` C-backend
gaps: a builtin present in the interpreter (and documented as 3-backend)
that the C backend never got.

**Fixed upstream (mere v0.1.14):** added the `print_err` case to the C backend (`fprintf(stderr, "%s\n", ...)`, mirroring `print` -> `puts`). Native `mk` now builds and writes task errors to stderr.

## (M3) 🟢 positive: task deps + topological run hit no language friction

M3 added task dependencies (`name [dep1 dep2]: command`) with depth-first
topological execution, run-once dedup (a `done` name list), and
short-circuit on the first nonzero exit. It was written in Mere with **no
friction**: a `Task` record, mutual recursion (`run_task` / `run_deps`),
tuple-returning `(exit_code, done_list)` threading, and `list_member` /
`list_filter` / `str_split` all just worked, interp and native identical.
Like mstat's stream redesign and mere-notes' CRDT, graph/recursion code is
where Mere is comfortable — the pains were the *edges* (the missing
`run` subprocess builtin P1, `print_err` on C P2), not the core.

## P3 🟢 `file_exists` missing in the C backend (fixed upstream, mere v0.1.15)

M4 (incremental builds) skips a task when its output exists and is newer
than its inputs. Checking "exists" uses `file_exists`, and guards
`file_mtime` (which raises on a missing path). `file_mtime` is on all
backends, but `file_exists` is interpreter-only, so the native build fails:

```
error: use of undeclared identifier 'file_exists'
```

Same family as P2 (`print_err`) and mq's `str_eq`: a filesystem builtin
present in the interpreter (and needed to guard the native-present
`file_mtime`) that the C backend never got.

**Fixed upstream (mere v0.1.15):** added the `file_exists` case to the C backend (`stat(path, &st) == 0`, next to `__lang_file_mtime`). Native `mk` incremental builds now work; the float mtime comparison rides the v0.1.11 structural `>`.
