This file is for humans 🧑

When creating AGENTS.md, these are the things that surfaced as necessary improvements. A workaround is documented in AGENTS.md, but we should
really fix the root cause.

1. Add idiomatic Ruby/RSpec example pair(s) to .cursor/rules/testing.mdc. Try to cover a bit of everything (e.g. mock, nested examples, naming context/it blocks).
1. Move .cursor/rules/ to [skills](https://agentskills.io)? It seems like more of a standard.
1. Can we just have good human-facing docs (similar to what we have in `docs/`), instead of 99% of the AI instructions we have today? We'll likely need to have some AI glue left, but why not just have readable plain language docs for everyone?
1. Possibly the whole `Gotchas` section in AGENTS.md.
1. Improve native dev onboarding: refine `rake native_dev:setup` or document a direct [bear](https://github.com/rizsotto/Bear) setup?
1. Create separate, specialized, and detailed personas for useful repository tasks, to avoid adding too much information to AGENTS.md.
Existing personas were left as-is in `.cursor/rules/`, but we should revise them, now that a global AGENTS.md exists.
Some persona ideas:
    1. `code-typing` – specialist on non-trivial typying issues. Can create "accurate" types, solve complicated patterns we've identified prior, and populate 3rd-party gems in `vendor/rbs`.
    1. `setup` – helps new dev on dd-trace-rb onboarding.
    1. `ci-failure` – tells you why your commit is failing on GitHub or Gitlab (e.g using remote APIs).
    1. `code-reviewer` – ensures reviewer agents gather the right resources.
    1. `gem-files` – helps with updates to Appraisals, `Matrixfile`, `Rakefile`, and dependency matrices.
    1. `instrumentation` - knows how to create/maintain contrib integrations (possibly seperate personas per-product).
    1. `native-extensions` - helps with native extensions changes (`libdatadog` vs "other ext's" are likely separate personas). Helps with MacOS compilation/testing too.
    1. `new-ruby-version` – stewards MRI/JRuby/TruffleRuby version bumps.
    1. TODO: QUESTION TO REVIEWERS: `release` - not sure what this one would do exactly
    1. TODO: QUESTION TO REVIEWERS: `security-auditor` - not sure what this one would do exactly
1. Let's try to use the official `@api public` YARD tag, instead of our custom `@public_api` tag: https://rubydoc.info/gems/yard/0.9.38/file/docs/Tags.md#api
