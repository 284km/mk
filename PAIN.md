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
