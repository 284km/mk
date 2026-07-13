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
