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
- [ ] M3: task dependencies (`deps`), topological order
- [ ] M4: incremental (skip if output newer than inputs; `file_mtime` exists)
- [ ] M5: parallel independent tasks (`spawn` / `channel`)
