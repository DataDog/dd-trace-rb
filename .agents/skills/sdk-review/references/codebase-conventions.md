# Codebase conventions

Repo-specific idioms: configuration, logging, shared helpers, test patterns, and build tooling. [AGENTS.md](../../../../AGENTS.md) also applies.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line and no `Not when:` applies, or when it has a clear problem in this lens's area that no rule covers (mark it `no rule`). Cite the rule ID and name the helper or pattern to use.

## 1. Configuration and environment

### CONV-1.1: Keep `DATADOG_ENV.fetch` defaults as `String?`
- Flag: a non-string default passed to `DATADOG_ENV.fetch`, which widens the return type.
- ❌ `DATADOG_ENV.fetch(Configuration::Ext::Metrics::ENV_DEFAULT_PORT, Ext::DEFAULT_PORT).to_i`
- ✅ `DATADOG_ENV.fetch(Configuration::Ext::Metrics::ENV_DEFAULT_PORT, Ext::DEFAULT_PORT.to_s).to_i`

### CONV-1.2: Spell out words in env var constant names, but keep the env var string identical to other Datadog SDKs
- Flag: an abbreviated constant name for an env var (`ENV_..._CTX`), or a new `DD_*` env var string that differs from the one other SDKs already use for the same setting, including expanding an abbreviation (`CTX`) or dropping an `EXPERIMENTAL` prefix.
- Not when: no other SDK defines the setting yet; then follow the product's `DD_<PRODUCT>_*` prefix.
- ❌ `ENV_OTEL_CTX_ENABLED = "DD_TRACE_OTEL_CONTEXT_ENABLED"`
- ✅ `ENV_OTEL_CONTEXT_ENABLED = "DD_TRACE_OTEL_CTX_ENABLED"` (the string other SDKs already read)

## 2. Types

The [write-rbs skill](../../write-rbs/SKILL.md) also applies.

### CONV-2.1: Fix the type or the code instead of adding `steep:ignore` or casts
- Flag: a new `steep:ignore` (especially for an argument type mismatch, or a `NoMethod` whose target is unclear), inline `#:` casts that compensate for a wrong signature, duplicated branches, or code rewritten only to attach an annotation. For a `respond_to?` guard or chain that Steep can't narrow, narrow with `is_a?` against the real type, or move the whole condition into a named predicate (for example, `datadog_ci_enabled?`). See [steep-annotations.md](../../write-rbs/references/steep-annotations.md).
- ❌ `value.reset! if value.respond_to?(:reset!) # steep:ignore NoMethod`
- ✅ `value.reset! if value.is_a?(Configuration::Base)`

### CONV-2.2: Declare signatures for Ruby `private` methods under `private` in RBS
- Flag: an RBS method declared public while the Ruby method is `private`, so explicit-receiver calls pass type checking and fail at runtime.

### CONV-2.3: Put signatures for third-party or stdlib gaps in `vendor/rbs`, not `sig/`
- Flag: a new `sig/` file declaring types for a gem or stdlib API; `sig/` carries only this gem's types.

### CONV-2.4: Add `# @type` annotations only where Steep needs them
- Flag: a new `# @type self:` or `# @type var:` annotation that fixes no Steep error.

## 3. Files, tests, and the test matrix

### CONV-3.1: Match directory and file names to module names
- Flag: a directory or file named after a wire or endpoint name instead of its constant (`flagevaluation/` for `FlagEvaluation`).

### CONV-3.2: Use `instance_double(RealClass)` and real SDK types in specs
- Flag: every string-named double (`double("Writer")`), and every `Struct.new`, `OpenStruct`, or ad hoc class defined in a spec to stand in for a type that this gem or a dependency SDK defines. Report each file.
- ❌ `writer = double("Writer")`
- ✅ `writer = instance_double(Datadog::OpenFeature::FlagEvaluation::Writer)`

### CONV-3.3: Enable the `*-latest` `Matrixfile` entry when adding support for a new library major version
- Flag: a PR adding support for a new major version while the matching `*-latest` entry stays disabled.

### CONV-3.4: Regenerate gemfile lockfiles when bumping dependency versions
- Flag: a dependency version bump with no matching `gemfiles/*.lock` updates; regenerate them with `bundle exec rake dependency:generate`.

### CONV-3.5: Name shared test matrix groups generically
- Flag: a new `Matrixfile` group named with a product prefix (`appsec-active-record`) when other suites could reuse it.

### CONV-3.6: Don't add Unicode box-drawing dividers
- Flag: comment dividers such as `# ─── Section ───` in code or specs.

## 4. Linting

### CONV-4.1: Don't disable or re-enable cops without replacement enforcement
- Flag: a cop disabled for convenience (for example, `Layout/LeadingCommentSpace` for Steep annotations) without equivalent enforcement, or a re-enabled cop that `.standard_todo.yml` deliberately disables. Standard can only disable cops, so `.rubocop.yml` enforces the preferred style.

### CONV-4.2: Treat RuboCop as the full linter
- Flag: tooling, editor configuration, or docs that run only `standardrb` or `rake standard` as the linter; RuboCop runs Standard plus the repo's extra cops.

### CONV-4.3: Enforce mechanical rules with a cop instead of documenting them
- Flag: a new rule in `AGENTS.md`, a skill, or a code comment that asks people or agents to follow a mechanical code shape (for example, struct inheritance or quoting), or a new hand-maintained format (changelog entries, file naming), that a RuboCop cop or a small lint task could enforce. Name the cop or the check to add.

## 5. Changelog and pull requests

The [write-changelog skill](../../write-changelog/SKILL.md) also applies.

### CONV-5.1: Use official product names and supported platforms in changelog entries
- Flag: unofficial names ("automatic instrumentation" instead of "Single Step Instrumentation"), or an entry advertising a fix for an unsupported platform such as JRuby. See [JRubyDeprecation.md](../../../../docs/JRubyDeprecation.md).

### CONV-5.2: Explain why in the PR description, and spell out customer impact for behaviour changes
- Flag: a PR body without a motivation; one that changes customer-visible behaviour (span resources, setting defaults) without describing the impact; or a PR title, body, or code comment that cites an RFC or ticket ID (for example, `RFC-1113`) as the explanation. Ask for a concrete example of the behaviour instead; the ID cannot stay in the PR text as a substitute.

### CONV-5.3: Squash large transient files inside the branch before merging
- Flag: a branch whose commits add and later remove or rewrite large files (fixtures, generated data). The repo merges with merge commits, so squash the branch itself.

## Don't flag
- `-gnu` images-rb tags in pins that predate the `-gnu-gcc-g<sha>` tags.
