# Typing Notes (Reusable Fix Patterns)

Purpose: capture patterns that successfully solve Steep/RBS typing issues so they can be reused across folder steps.

## Entry Format

- id: short stable label
- date: YYYY-MM-DD
- scope: file(s) where it was observed
- offence: file:line + diagnostic ID + key message
- cause: why Steep/RBS fails
- when-it-applies: concrete code shape where this pattern is valid
- fix-pattern: minimal code/signature transformation
- upstream-bug:
  - confidence: `high|medium|low`
  - status: `yes|no|unknown`
  - canonical-link: URL if known
  - note: short rationale

## Patterns

### worker-thread-local-narrowing

- id: `worker-thread-local-narrowing`
- date: `2026-02-13`
- scope: `lib/datadog/core/workers/async.rb`
- offence:
  - `lib/datadog/core/workers/async.rb:50` `Ruby::NoMethod` `Type (::Thread | nil) does not have method join`
  - `lib/datadog/core/workers/async.rb:58` `Ruby::NoMethod` `Type (::Thread | nil) does not have method terminate`
  - `lib/datadog/core/workers/async.rb:81` `Ruby::NoMethod` `Type (::Thread | nil) does not have method alive?`
- cause: nil narrowing is lost across repeated method/ivar reads (`worker`) in the same method body.
- when-it-applies: guard clauses/checks are present, but method calls still target a repeated nullable receiver.
- fix-pattern:
  - capture receiver once: `thread = worker`
  - guard using local: `return ... unless thread&.alive?`
  - call methods on local: `thread.join(...)`, `thread.status`, etc.
- upstream-bug:
  - confidence: `medium`
  - status: `unknown`
  - canonical-link: none
  - note: looks like flow-narrowing limitation, but no canonical issue is linked yet.

### prepend-super-unexpected-super

- id: `prepend-super-unexpected-super`
- date: `2026-02-13`
- scope: `lib/datadog/core/workers/async.rb`
- offence:
  - `lib/datadog/core/workers/async.rb:34` `Ruby::UnexpectedSuper` `No superclass method perform defined` (information severity)
- cause: Steep has known limitations resolving `prepend` method chains with `super`.
- when-it-applies: method is defined in a prepended module and calls `super`, while the target method exists via runtime composition.
- fix-pattern:
  - keep runtime code unchanged
  - add minimal local suppression on the `super(...)` call
  - add canonical upstream issue link. no need to expand.
- upstream-bug:
  - confidence: `high`
  - status: `yes`
  - canonical-link: `https://github.com/soutaro/steep/issues/332`
  - note: canonical upstream bug exists for prepend + super producing `UnexpectedSuper`.
