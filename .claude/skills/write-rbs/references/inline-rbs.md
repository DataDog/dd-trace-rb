# Inline RBS

Use a trailing `# :` in the `.rb` file — either as a one-off cast to narrow a
single expression, or as a file's whole signature in place of `sig/`

## Rules

- Standalone `sig/` is the repo default — inline mode is opt-in per file via
  `inline: true` in the `Steepfile`; without that line a file's `# :` signatures
  go unchecked
- SHOULD keep a file inline only when it is small and self-contained; otherwise
  mirror it in `sig/`
- NEVER split one file across both an inline `# :` signature and a `sig/` `.rbs` —
  pick one per file
- MUST write an inline method signature with types only, no argument names —
  `# : (Time, Time) -> bool`
- A trailing `# : Type` also narrows one expression Steep infers too widely, even
  in a `sig/`-checked file — SHOULD prefer it over reshaping correct code

## Examples

Cast a single expression to the type Steep cannot infer:

```ruby
# Good — narrows the widened expression to what it really is
uri = URI(endpoint) # : URI::HTTP

# Bad — casting to untyped discards the type instead of narrowing it
uri = URI(endpoint) # : untyped
```

Annotate an empty literal — it has no element type to infer:

```ruby
# Good — later pushes are checked against the element type
metrics = [] # : Array[[String, Numeric]]

# Bad — bare [] infers Array[untyped]; every push goes unchecked
metrics = []
```

In an `inline: true` file, the `# :` carries the whole signature:

```ruby
attr_reader :start # : Time

# : (Time, Time) -> bool
def duration_below_threshold?(start, finish)
  (finish - start) < minimum_duration_seconds
end
```
