# mk

A tiny task runner written in [Mere](https://github.com/merelang/mere) and
compiled to a native binary (`mere -c | clang`).

It reads a `mkfile` — lines of `name: shell command` — and runs the named
task, propagating its exit code:

```
$ cat mkfile
build: clang -O2 main.c -o app
test:  ./app --check
clean: rm -f app

$ mk build      # runs "clang -O2 main.c -o app", exits with its code
$ mk nope       # → stderr: "mk: no such task: nope", exit 1

A dep group in brackets runs sequentially; add `&` to run it in parallel:

```
fast [lint unit e2e]&: echo all checks passed
```
```

## Why this exists

`mk` is a dogfood app for Mere, chosen to grow the one capability the
language was missing: **running external programs**. Building it is what
motivated Mere's `run : str -> int` builtin (v0.1.13) and the C backend's
`print_err` (v0.1.14). See [PAIN.md](./PAIN.md) — the friction log is as
much the point as the tool.

## Build

```
mere -c main.mere > m.c && clang -O2 m.c -o mk
```

## Roadmap

- [x] M0: run one command, propagate exit code (`run`)
- [x] M2: `mkfile` with `name: command`, run a named task
- [x] M3: task dependencies (`name [deps]: cmd`), topological order
- [x] M4: incremental (`name (out: in1 in2): cmd` — skip if `out` newer than inputs)
- [x] M5: parallel dep groups (`name [a b c]&: cmd` via `par_map`; deps must be independent)
