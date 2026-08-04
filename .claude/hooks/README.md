# Hooks

Claude Code hooks for this repo. A hook is a small script Claude Code runs
around tool calls — here, one Ruby file per hook.

## Writing a hook

A hook is two files: `<name>.rb` holds the runtime, `<name>.test.rb` holds its
tests. The runtime stays pure so it compiles cleanly; the test file
`require_relative`s it and drives it. Requiring the runtime runs the whole file,
so the last line guards against firing when the test loads it:

```ruby
# runs as a hook or a compiled binary, but not when required by the test
Runner.new(ARGV).run($stdin.read) unless $PROGRAM_NAME.end_with?(".test.rb")
```

Run the hook the way Claude Code does, with the payload as JSON on stdin:

```sh
ruby <name>.rb <args>
```

## Testing

```sh
make test               # every hook's tests (unit + smoke), under CRuby
ruby <name>.test.rb     # a single hook
```

Each test file carries two suites. The **unit** suite exercises the hook's logic
in process. The **smoke** suite runs the hook end to end as a subprocess against
a set of scenarios, once per available runner: CRuby always, and the compiled
binary when one is present. CRuby is the oracle — the binary must match it byte
for byte, so a miscompile shows up as a divergence. With no binary built, smoke
runs CRuby only and says so.

## Shims

`settings.json` never points at a Ruby file directly. It points at a shim in
`shims/`, which runs the compiled binary when one exists and falls back to plain
Ruby otherwise. That keeps the wiring stable whether or not a native build is
present:

```sh
"command": "sh \"$CLAUDE_PROJECT_DIR/.claude/hooks/shims/<name>\" <args>"
```

## Native compilation

Ruby's cold start is slow for something that fires on every tool call, so a hook
can be compiled ahead of time into a standalone native binary with [Spinel],
which starts roughly thirty times faster. Spinel is not on `PATH` by default;
build it once, then compile:

```sh
make bootstrap   # fetch + build Spinel into ~/.cache/spinel (one-time)
make compile     # every hook -> compiled/<name>
```

The result lands in `compiled/<name>`, and the shim prefers it automatically.
Binaries are architecture- and OS-specific, so `compiled/` is gitignored —
everyone builds their own, and plain Ruby remains the portable fallback.

Spinel only supports a subset of Ruby, so mind the gaps. `Hash#dig`, for one,
is unsupported — reach for `Hash#fetch` instead. Because the binary is
architecture-specific and compiled separately from CRuby, re-verify after any
hook change: `make compile && make test`. The smoke suite then diffs the fresh
binary against CRuby and fails on any divergence.

## Hooks in this repo

### require-skill

Loads a required skill before Claude edits a matching path, so the skill's
guidance is in context first. It matches the `Edit` and `Write` tools, where
Claude hand-authors file content. It deliberately does not match `Bash`: shell
tools like `sed`, `cp`, `mv`, and `tee` transform or copy existing bytes rather
than author new content, so there is nothing for the skill to guide, and reliably
detecting a write to a guarded path inside an arbitrary command line is not
feasible.

## Links

The [Claude Code hooks guide][hooks] covers the payload shape and decision
protocol, and [Spinel] documents what compiles and what does not.

[hooks]: https://docs.claude.com/en/docs/claude-code/hooks
[Spinel]: https://github.com/matz/spinel
