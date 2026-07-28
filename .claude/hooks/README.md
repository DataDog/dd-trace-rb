# Hooks

Claude Code hooks for this repo. A hook is a small script Claude Code runs
around tool calls — here, one Ruby file per hook.

## Writing a hook

Keep it to a single file. Logic and tests live together, with the tests tucked
behind a `TEST=1` guard so they never run when Claude Code invokes the hook:

```ruby
Runner.new(ARGV).run($stdin.read) unless ENV["TEST"] == "1"

# tests below — only loaded when TEST=1
```

Run the hook the way Claude Code does, with the payload as JSON on stdin:

```sh
ruby <name>.rb <args>
```

And run its tests by flipping the guard:

```sh
TEST=1 ruby <name>.rb
```

A hook should stay small, so inline tests are the default. If one ever grows
complex enough that the tests get in the way, pull them into their own file —
but reach for that only when the single file genuinely stops paying off.

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
which starts roughly thirty times faster. Build one like this:

```sh
ruby compile.rb <name>   # one hook (name, name.rb, or a path all work)
ruby compile.rb          # every hook in this directory
```

The result lands in `compiled/<name>`, and the shim prefers it automatically.
Binaries are architecture- and OS-specific, so `compiled/` is gitignored —
everyone builds their own, and plain Ruby remains the portable fallback.

Spinel only supports a subset of Ruby, so mind the gaps. `Hash#dig`, for one,
is unsupported — reach for `Hash#fetch` instead. After changing a hook,
recompile and re-run its tests against the binary to confirm the native path
still behaves like CRuby.

## Links

The [Claude Code hooks guide][hooks] covers the payload shape and decision
protocol, and [Spinel] documents what compiles and what does not.

[hooks]: https://docs.claude.com/en/docs/claude-code/hooks
[Spinel]: https://github.com/matz/spinel
