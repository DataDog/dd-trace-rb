# JRuby Support Deprecation

As of  **March 2026**, JRuby support in the
[Ruby APM Tracing Library](https://github.com/DataDog/dd-trace-rb) (`datadog` gem) is deprecated.

This affects only [JRuby](https://www.jruby.org/) (Ruby on top of the Java VM).
Ruby releases from [ruby-lang.org](https://www.ruby-lang.org/) (MRI/CRuby) remain fully supported.

## Recommended action

Pin the `datadog` gem to **`~> 2.30.0`**, the last version fully tested with JRuby:

```ruby
# Gemfile
gem 'datadog', '~> 2.30.0'
```

This keeps your JRuby services on a known-good release while allowing patch-level updates within `2.30.x`.

If you need to lock to an exact version instead:

```ruby
# Gemfile
gem 'datadog', '2.30.0'

# or

gem 'datadog', '= 2.30.0'
```

## FAQ

### What does "deprecated" mean in practice?

Versions released after July 2026 **may still work** on JRuby, but they will no longer be
tested or officially supported. Bug reports specific to JRuby will be handled on a best-effort
basis without SLA guarantees.

### Which JRuby versions are affected?

All JRuby versions (9.2, 9.3, 9.4, 10.x). After deprecation, no JRuby version will be
included in the CI test matrix.

### What happens if I don't pin?

Bundler will install the latest `datadog` release, which may include changes that have not
been validated on JRuby. Pinning gives you control over when (and whether) to upgrade.

### What if I'm still on `ddtrace` (1.x)?

The `ddtrace` gem (1.x) is [end-of-life](Compatibility.md#support-eol). If you are
considering an upgrade, see the [Upgrade Guide](UpgradeGuide2.md) for migration details.

### Which Datadog features already don't work on JRuby?

The following features require MRI/CRuby and are **not available** on JRuby regardless
of gem version:

- Continuous Profiling
- Dynamic Instrumentation
- Error Tracking
- Crashtracking

APM Tracing and AppSec work on JRuby within the pinned version range.

### Will existing JRuby-specific code be removed?

JRuby-specific workarounds will remain in the current 2.x release line. The deprecation
means we stop actively testing and maintaining JRuby compatibility, not that we
actively break it. In a future major version (3.x), JRuby-specific code may be removed
entirely.

### Where can I get help?

If you have questions, open a [GitHub issue](https://github.com/DataDog/dd-trace-rb/issues)
or contact [Datadog Support](https://docs.datadoghq.com/help/).
