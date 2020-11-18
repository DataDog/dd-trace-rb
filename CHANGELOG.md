# Changelog

## [Unreleased]

## [0.43.0] - 2020-11-18

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.43.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.42.0...v0.43.0

### Added

- Background job custom error handlers (#1212) (@norbertnytko)
- Add "multi" methods instrumentation for Rails cache (#1217) (@michaelkl)
- Support custom error status codes for Grape (#1238)
- Cucumber integration (#1216)
- RSpec integration (#1234)
- Validation to `:on_error` argument on `Datadog::Tracer#trace` (#1220)

### Changed

- Update `TokenBucket#effective_rate` calculation (#1236)

### Fixed

- Avoid writer reinitialization during shutdown (#1235, #1248)
- Fix configuration multiplexing (#1204, #1227)
- Fix misnamed B3 distributed headers (#1226, #1229)
- Correct span type for AWS SDK (#1233)
- Correct span type for internal Pin on HTTP clients (#1239)
- Reset trace context after fork (#1225)

### Refactored

- Improvements to test suite (#1232, #1244)
- Improvements to documentation (#1243, #1218) (@cjford)

### Removed

## [0.42.0] - 2020-10-21

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.42.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.41.0...v0.42.0

### Added

- Increase Resque support to include 2.0  (#1213) (@erict-square)

- Improve gRPC Propagator to support metadata array values (#1203) (@mdehoog)

- Add CPU benchmarks, diagnostics to tests (#1188, #1198)

- Access active correlation by Thread (#1200)

- Improve delayed_job instrumentation (#1187) (@norbertnytko)

### Changed

### Fixed

- Improve Rails `log_injection` option to support more Lograge formats (#1210) (@Supy)

- Fix Changelog (#1199) (@y-yagi)

### Refactored

- Refactor Trace buffer into multiple components (#1195)

## [0.41.0] - 2020-09-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.41.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.40.0...v0.41.0

### Added

- Improve duration counting using monotonic clock (#424, #1173) (@soulcutter)

### Changed

- Add peer.service tag to external services and skip tagging external services with language tag for runtime metrics (#934, #935, #1180)
  - This helps support the way runtime metrics are associated with spans in the UI.
- Faster TraceBuffer for CRuby (#1172)
- Reduce memory usage during gem startup (#1090)
- Reduce memory usage of the HTTP transport (#1165)

### Fixed

- Improved prepared statement support for Sequel  integrations (#1186)
- Fix Sequel instrumentation when executing literal strings (#1185) (@matchbookmac)
- Remove explicit `Logger` class verification (#1181) (@bartekbsh)
  - This allows users to pass in a custom logger that does not inherit from `Logger` class.
- Correct tracer buffer metric counting (#1182)
- Fix Span#pretty_print for empty duration (#1183)

### Refactored

- Improvements to test suite & CI (#1179, #1184, #1177, #1178, #1176)
- Reduce generated Span ID range to fit in Fixnum (#1189)

## [0.40.0] - 2020-09-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.40.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.39.0...v0.40.0

### Added

- Rails `log_injection` option to auto enable log correlation (#1157)
- Que integration (#1141, #1146) (@hs-bguven)
- `Components#startup!` hook (#1151)
- Code coverage report (#1159)
  - Every commit now has a `coverage` CI step that contains the code coverage report. This report can be found in the `Artifacts` tab of that CI step, under `coverage/index.html`.

### Changed

- Use a single top level span for Racecar consumers (#1150) (@dasch)

### Fixed

- Sinatra nested modular applications possibly leaking spans (#1035, #1145)
  
  * **BREAKING** for nested modular Sinatra applications only:
    ```ruby
    class Nested < Sinatra::Base
    end
    
    class TopLevel < Sinatra::Base
      use Nested # Nesting happens here
    end
    ```
  * Non-breaking for classic applications nor modular non-nested applications.
  
  Fixes issues introduced by #1015 (in 0.35.0), when we first introduced Sinatra support for modular applications.
  
  The main issue we had to solve for modular support is how to handle nested applications, as only one application is actually responsible for handling the route. A naive implementation would cause the creation of nested `sinatra.request` spans, even for applications that did not handle the request. This is technically correct, as Sinatra is traversing that middleware, accruing overhead, but that does not aligned with our existing behavior of having a single `sinatra.request` span.
  
  While trying to achieve backwards-compatibility, we had to resort to a solution that turned out brittle: `sinatra.request` spans had to start in one middleware level and finished it in another. This allowed us to only capture the `sinatra.request` for the matching route, and skip the non-matching one. This caused unexpected issues on some user setups, specially around Sinatra middleware that created spans in between the initialization and closure of `sinatra.request` spans.
  
  This change now address these implementation issues by creating multiple `sinatra.request`, one for each traversed Sinatra application, even non-matching ones. This instrumentation is more correct, but at the cost of being a breaking change for nested modular applications.
  
  Please see #1145 for more information, and example screenshots on how traces for affected applications will look like.

- Rack/Rails span error propagation with `rescue_from` (#1155, #1162)
- Prevent logger recursion during startup (#1158)
- Race condition on new worker classes (#1154)
  - These classes represent future work, and not being used at the moment.

### Refactored

- Run CI tests in parallel (#1156)
- Migrate minitest tests to RSpec (#1127, #1128, #1133, #1149, #1152, #1153)
- Improvements to test suite (#1134, #1148, #1163)
- Improvements to documentation (#1138)

### Removed

- **Ruby 1.9 support ended, as it transitions from Maintenance to End-Of-Life (#1137)**
- GitLab status check when not applicable (#1160)
  - Allows for PRs pass all status checks once again. Before this change, a `dd-gitlab/copy_to_s3` check would never leave the "Pending" status. This check tracks the deployment of a commit to an internal testing platform, which currently only happens on `master` branch or when manually triggered internally.

## [0.39.0] - 2020-08-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.39.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.38.0...v0.39.0

### Added

- JRuby 9.2 support (#1126)
- Sneakers integration (#1121) (@janz93)

### Changed

- Consistent environment variables across languages (#1115)
- Default logger level from WARN to INFO (#1120) (@gingerlime)
  - This change also reduces the startup environment log message to INFO level (#1104)

### Fixed

- HTTP::StateError on error responses for http.rb (#1116, #1122) (@evan-waters)
- Startup log error when using the test adapter (#1125, #1131) (@benhutton)
- Warning message for Faraday < 1.0 (#1129) (@fledman, @tjwp)
- Propagate Rails error message to Rack span (#1124)

### Refactored

- Improved ActiveRecord documentation (#1119)
- Improvements to test suite (#1105, #1118)

## [0.38.0] - 2020-07-13

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.38.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.37.0...v0.38.0

### Added

- http.rb integration (#529, #853)
- Kafka integration (#1070) (@tjwp)
- Span#set_tags (#1081) (@DocX)
- retry_count tag for Sidekiq jobs (#1089) (@elyalvarado)
- Startup environment log (#1104, #1109)
- DD_SITE and DD_API_KEY configuration (#1107)

### Changed

- Auto instrument Faraday default connection (#1057)
- Sidekiq client middleware is now the same for client and server (#1099) (@drcapulet)
- Single pass SpanFilter (#1071) (@tjwp)

### Fixed

- Ensure fatal exceptions are propagated (#1100)
- Respect child_of: option in Tracer#trace (#1082) (@DocX)
- Improve Writer thread safety (#1091) (@fledman)

### Refactored

- Improvements to test suite (#1092, #1103)

## [0.37.0] - 2020-06-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.37.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.36.0...v0.37.0

### Refactored

- Documentation improvements regarding Datadog Agent defaults (#1074) (@cswatt)
- Improvements to test suite (#1043, #1051, #1062, #1075, #1076, #1086)

### Removed

- **DEPRECATION**: Deprecate Contrib::Configuration::Settings#tracer= (#1072, #1079)
  - The `tracer:` option is no longer supported for integration configuration. A deprecation warning will be issued when this option is used.
  - Tracer instances are dynamically created when `ddtrace` is reconfigured (through `Datadog.configure{}` calls).

    A reference to a tracer instance cannot be stored as it will be replaced by a new instance during reconfiguration.

    Retrieving the global tracer instance, by invoking `Datadog.tracer`, is the only safe mechanism to acquire the active tracer instance.

    Allowing an integration to set its tracer instance is effectively preventing that integration from dynamically retrieving the current active tracer in the future, thus causing it to record spans in a stale tracer instance. Spans recorded in a stale tracer instance will look disconnected from their parent context.

- **BREAKING**: Remove Pin#tracer= and DeprecatedPin#tracer= (#1073)
  - The `Pin` and `DeprecatedPin` are internal tools used to provide more granular configuration for integrations.
  - The APIs being removed are not public nor have been externally documented. The `DeprecatedPin` specifically has been considered deprecated since 0.20.0.
  - This removal is a continuation of #1079 above, thus carrying the same rationale.

### Migration

- Remove `tracer` argument provided to integrations (e.g. `c.use :rails, tracer: ...`).
- Remove `tracer` argument provided to `Pin` or `DeprecatedPin` initializers (e.g. `Pin.new(service, tracer: ...)`).
- If you require a custom tracer instance, use a global instance configuration:
    ```ruby
    Datadog.configure do |c|
      c.tracer.instance = custom_tracer
    end
    ```

## [0.36.0] - 2020-05-27

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.36.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.35.2...v0.36.0

### Changed

- Prevent trace components from being re-initialized multiple times during setup (#1037)

### Fixed

- Allow Rails patching if Railties are loaded (#993, #1054) (@mustela, @bheemreddy181, @vramaiah)
- Pin delegates to default tracer unless configured (#1041)

### Refactored

- Improvements to test suite (#1027, #1031, #1045, #1046, #1047)

## [0.35.2] - 2020-05-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.35.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.35.1...v0.35.2

### Fixed

- Internal tracer HTTP requests generating traces (#1030, #1033) (@gingerlime)
- `Datadog.configure` forcing all options to eager load (#1032, #1034) (@kelvin-acosta)

## [0.35.1] - 2020-05-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.35.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.35.0...v0.35.1

### Fixed

- Components#teardown! NoMethodError (#1021, #1023) (@bzf)

## [0.35.0] - 2020-04-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.35.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.34.2...v0.35.0

### Added

- Chunk large trace payloads before flushing (#818, #840)
- Support for Sinatra modular apps (#486, #913, #1015) (@jpaulgs, @tomasv, @ZimbiX)
- active_job support for Resque (#991) (@stefanahman, @psycholein)
- JRuby 9.2 to CI test matrix (#995)
- `TraceWriter` and `AsyncTraceWriter` workers (#986)
- Runtime metrics worker (#988)

### Changed

- Populate env, service, and version from tags (#1008)
- Extract components from configuration (#996)
- Extract logger to components (#997)
- Extract runtime metrics worker from `Writer` (#1004)
- Improvements to Faraday documentation (#1005)

### Fixed

- Runtime metrics not starting after #write (#1010)

### Refactored

- Improvements to test suite (#842, #1006, #1009)

## [0.34.2] - 2020-04-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.34.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.34.1...v0.34.2

### Changed

- Revert Rails applications setting default `env` if none are configured. (#1000) (@errriclee)

## [0.34.1] - 2020-04-02

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.34.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.34.0...v0.34.1

### Changed

- Rails applications set default `service` and `env` if none are configured. (#990)

### Fixed

- Some configuration settings not applying (#989, #990) (@rahul342)

## [0.34.0] - 2020-03-31

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.34.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.33.1...v0.34.0

### Added

- `Datadog::Event` for simple pub-sub messaging (#972)
- `Datadog::Workers` for trace writing (#969, #973)
- `_dd.measured` tag to some integrations for more statistics (#974)
- `env`, `service`, `version`, `tags` configuration for auto-tagging (#977, #980, #982, #983, #985)
- Multiplexed configuration for Ethon, Excon, Faraday, HTTP integrations (#882, #953) (@stormsilver)

### Fixed

- Runtime metrics configuration dropping with new writer (#967, #968) (@ericmustin)
- Faraday "unexpected middleware" warnings on v0.x (#965, #971)
- Presto configuration (#975)
- Test suite issues (#981)

## [0.33.1] - 2020-03-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.33.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.33.0...v0.33.1

### Fixed

- NoMethodError when activating instrumentation for non-existent library (#964, #966) (@roccoblues, @brafales)

## [0.33.0] - 2020-03-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.33.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.32.0...v0.33.0

### Added

- Instrumentation for [Presto](https://github.com/treasure-data/presto-client-ruby) (#775, #920, #961) (@ahammel, @ericmustin)
- Sidekiq job argument tagging (#933) (@mantrala)
- Support for multiple Redis services (#861, #937, #940) (@mberlanda)
- Support for Sidekiq w/ Delayed extensions (#798, #942) (@joeyAghion)
- Setter/reset behavior for configuration options (#957)
- Priority sampling rate tag (#891)

### Changed

- Enforced minimum version requirements for instrumentation (#944)
- RubyGems minimum version requirement 2.0.0 (#954) (@Joas1988)
- Relaxed Rack minimum version to 1.1.0 (#952)

### Fixed

- AWS instrumentation patching when AWS is partially loaded (#938, #945) (@letiesperon, @illdelph)
- NoMethodError for RuleSampler with priority sampling (#949, #950) (@BabyGroot)
- Runtime metrics accumulating service names when disabled (#956)
- Sidekiq instrumentation incompatibility with Rails 6.0.2 (#943, #947) (@pj0tr)
- Documentation tweaks (#948, #955) (@mstruve, @link04)
- Various test suite issues (#930, #932, #951, #960)

## [0.32.0] - 2020-01-22

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.32.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.31.1...v0.32.0

### Added

- New transport: Datadog::Transport::IO (#910)
- Dual License (#893, #921)

### Changed

- Improved annotation of `net/http` spans during exception (#888, #907) (@djmb, @ericmustin)
- RuleSampler is now the default sampler; no behavior changes by default (#917)

### Refactored

- Improved support for multiple tracer instances (#919)
- Improvements to test suite (#909, #928, #929)

## [0.31.1] - 2020-01-15

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.31.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.31.0...v0.31.1

### Fixed

- Implement SyncWriter#stop method (#914, #915) (@Yurokle)
- Fix references to Datadog::Tracer.log (#912)
- Ensure http.status_code tag is always a string (#927)

### Refactored

- Improvements to test suite & CI (#911, #918)

## [0.31.0] - 2020-01-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.31.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.30.1...v0.31.0

### Added

- Ruby 2.7 support (#805, #896)
- ActionCable integration (#132, #824) (@renchap, @ericmustin)
- Faraday 1.0 support (#906)
- Set resource for Rails template spans (#855, #881) (@djmb)
- at_exit hook for graceful Tracer shutdown (#884)
- Environment variables to configure RuleSampler defaults (#892)

### Changed

- Updated partial trace flushing to conform with new back-end requirements (#845)
- Store numeric tags as metrics (#886)
- Moved logging from Datadog::Tracer to Datadog::Logger (#880)
- Changed default RuleSampler rate limit from unlimited to 100/s (#898)

### Fixed

- SyncWriter incompatibility with Transport::HTTP::Client (#903, #904) (@Yurokle)

### Refactored

- Improvements to test suite & CI (#815, #821, #841, #846, #883, #895)

## [0.30.1] - 2019-12-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.30.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.30.0...v0.30.1

### Fixed

- NoMethodError when configuring tracer with SyncWriter (#899, #900) (@Yurokle)
- Spans associated with runtime metrics when disabled (#885)

### Refactored

- Improvements to test suite & CI (#815, #821, #846, #883, #890, #894)

## [0.30.0] - 2019-12-04

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.30.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.29.1...v0.30.0

### Added

- Additional tracer health metrics (#867)
- Integration patching instrumentation (#871)
- Rule-based trace sampling (#854)

### Fixed

- Rails template layout name error (#872) (@djmb)

## [0.29.1] - 2019-11-26

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.29.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.29.0...v0.29.1

### Fixed

- Priority sampling not activating by default (#868)

## [0.29.0] - 2019-11-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.29.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.28.0...v0.29.0

### Added

- Tracer health metrics (#838, #859)

### Changed

- Default trace buffer size from 100 to 1000 (#865)
- Rack request start headers to accept more values (#832) (@JamesHarker)
- Faraday to apply default instrumentation out-of-the-box (#786, #843) (@mdross95)

### Fixed

- Synthetics trace context being ignored (#856)

### Refactored

- Tracer buffer constants (#851)

### Removed

- Some old Ruby 1.9 code (#819, #844)

## [0.28.0] - 2019-10-01

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.28.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.27.0...v0.28.0

### Added

- Support for Rails 6.0 (#814)
- Multiplexing on hostname/port for Dalli (#823)
- Support for Redis array arguments (#796, #817) (@brafales)

### Refactored

- Encapsulate span resource name in Faraday integration (#811) (@giancarlocosta)

## [0.27.0] - 2019-09-04

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.27.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.26.0...v0.27.0

Support for Ruby < 2.0 is *removed*. Plan for timeline is as follows:

 - 0.25.0: Support for Ruby < 2.0 is deprecated; retains full feature support.
 - 0.26.0: Last version to support Ruby < 2.0; any new features will not support 1.9.
 - 0.27.0: Support for Ruby < 2.0 is removed.

Version 0.26.x will receive only critical bugfixes for 1 year following the release of 0.26.0 (August 6th, 2020.)

### Added

- Support for Ruby 2.5 & 2.6 (#800, #802)
- Ethon integration (#527, #778) (@al-kudryavtsev)

### Refactored

- Rails integration into smaller integrations per component (#747, #762, #795)

### Removed

- Support for Ruby 1.9 (#791)

## [0.26.0] - 2019-08-06

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.26.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.25.1...v0.26.0

Support for Ruby < 2.0 is *deprecated*. Plan for timeline is as follows:

 - 0.25.0: Support for Ruby < 2.0 is deprecated; retains full feature support.
 - 0.26.0: Last version to support Ruby < 2.0; any new features will not support 1.9.
 - 0.27.0: Support for Ruby < 2.0 is removed.

Version 0.26.x will receive only critical bugfixes for 1 year following the release of 0.26.0 (August 6th, 2020.)

### Added

- Container ID tagging for containerized environments (#784)

### Refactored

- Datadog::Metrics constants (#789)

### Removed

- Datadog::HTTPTransport and related components (#782)

## [0.25.1] - 2019-07-16

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.25.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.25.0...v0.25.1

### Fixed

- Redis integration not quantizing AUTH command (#776)

## [0.25.0] - 2019-06-27

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.25.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.24.0...v0.25.0

Support for Ruby < 2.0 is *deprecated*. Plan for timeline is as follows:

 - 0.25.0: Support for Ruby < 2.0 is deprecated; retains full feature support.
 - 0.26.0: Last version to support Ruby < 2.0; any new features will not support 1.9.
 - 0.27.0: Support for Ruby < 2.0 is removed.

Version 0.26.x will receive only critical bugfixes for 1 year following the release of 0.26.0.

### Added

- Unix socket support for transport layer (#770)

### Changed

- Renamed 'ForcedTracing' to 'ManualTracing' (#765)

### Fixed

- HTTP headers for distributed tracing sometimes appearing in duplicate (#768)

### Refactored

- Transport layer (#628)

### Deprecated

- Ruby < 2.0 support (#771)
- Use of `Datadog::HTTPTransport` (#628)
- Use of `Datadog::Ext::ForcedTracing` (#765)

## [0.24.0] - 2019-05-21

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.24.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.3...v0.24.0

### Added

- B3 header support (#753)
- Hostname tagging option (#760)
- Contribution and development guides (#754)

## [0.23.3] - 2019-05-16

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.2...v0.23.3

### Fixed

- Integrations initializing tracer at load time (#756)

## [0.23.2] - 2019-05-10

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.1...v0.23.2

### Fixed

- Span types for HTTP, web, and some datastore integrations (#751)
- AWS integration not patching service-level gems (#707, #752) (@alksl, @tonypinder)
- Rails 6 warning for `parent_name` (#750) (@sinsoku)

## [0.23.1] - 2019-05-02

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.0...v0.23.1

### Fixed

- NoMethodError runtime_metrics for SyncWriter (#748)

## [0.23.0] - 2019-04-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.22.0...v0.23.0

### Added

- Error status support via tags for OpenTracing (#739)
- Forced sampling support via tags (#720)

### Fixed

- Wrong return values for Rake integration (#742) (@Redapted)

### Removed

- Obsolete service telemetry (#738)

## [0.22.0] - 2019-04-15

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.22.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.21.2...v0.22.0

In this release we are adding initial support for the **beta** [Runtime metrics collection](https://docs.datadoghq.com/tracing/advanced/runtime_metrics/?tab=ruby) feature.

### Changed

- Add warning log if an integration is incompatible (#722) (@ericmustin)

### Added

- Initial beta support for Runtime metrics collection (#677)

## [0.21.2] - 2019-04-10

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.21.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.21.1...v0.21.2

### Changed

- Support Mongo gem 2.5+ (#729, #731) (@ricbartm)

## [0.21.1] - 2019-03-26

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.21.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.21.0...v0.21.1

### Changed

- Support `TAG_ENABLED` for custom instrumentation with analytics. (#728)

## [0.21.0] - 2019-03-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.21.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.20.0...v0.21.0

### Added

- Trace analytics support (#697, #715)
- HTTP after_request span hook (#716, #724)

### Fixed

- Distributed traces with IDs in 2^64 range being dropped (#719)
- Custom logger level forced to warning (#681, #721) (@blaines, @ericmustin)

### Refactored

- Global configuration for tracing into configuration API (#714)

## [0.20.0] - 2019-03-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.20.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.19.1...v0.20.0

This release will log deprecation warnings for any usage of `Datadog::Pin`.
These changes are backwards compatible, but all integration configuration should be moved away from `Pin` and to the configuration API instead.

### Added

- Propagate synthetics origin header (#699)

### Changed

- Enable distributed tracing by default (#701)

### Fixed

- Fix Rack http_server.queue spans missing from distributed traces (#709)

### Refactored

- Refactor MongoDB to use instrumentation module (#704)
- Refactor HTTP to use instrumentation module (#703)
- Deprecate GRPC global pin in favor of configuration API (#702)
- Deprecate Grape pin in favor of configuration API (#700)
- Deprecate Faraday pin in favor of configuration API (#696)
- Deprecate Dalli pin in favor of configuration API (#693)

## [0.19.1] - 2019-02-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.19.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.19.0...v0.19.1

### Added

- Documentation for Lograge implementation (#683, #687) (@nic-lan)

### Fixed

- Priority sampling dropping spans (#686)

## [0.19.0] - 2019-01-22

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.19.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.3...v0.19.0

### Added

- Tracer#active_correlation for adding correlation IDs to logs. (#660, #664, #673)
- Opt-in support for `event_sample_rate` tag for some integrations. (#665, #666)

### Changed

- Priority sampling enabled by default. (#654)

## [0.18.3] - 2019-01-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.2...v0.18.3

### Fixed

- Mongo `NoMethodError` when no span available during `#failed`. (#674, #675) (@Azure7111)
- Rack deprecation warnings firing with some 3rd party libraries present. (#672)
- Shoryuken resource name when used with ActiveJob. (#671) (@aurelian)

## [0.18.2] - 2019-01-03

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.1...v0.18.2

### Fixed

- Unfinished Mongo spans when SASL configured (#658) (@zachmccormick)
- Possible performance issue with unexpanded Rails cache keys (#630, #635) (@gingerlime)

## [0.18.1] - 2018-12-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.0...v0.18.1

### Fixed

- ActiveRecord `SystemStackError` with some 3rd party libraries (#661, #662) (@EpiFouloux, @tjgrathwell, @guizmaii)

## [0.18.0] - 2018-12-18

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.3...v0.18.0

### Added

- Shoryuken integration (#538, #626, #655) (@steveh, @JustSnow)
- Sidekiq client integration (#602, #650) (@dirk)
- Datadog::Shim for adding instrumentation (#648)

### Changed

- Use `DD_AGENT_HOST` and `DD_TRACE_AGENT_PORT` env vars if available (#631)
- Inject `:connection` into `sql.active_record` event (#640, #649, #656) (@guizmaii)
- Return default configuration instead of `nil` on miss (#651)

## [0.17.3] - 2018-11-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.2...v0.17.3

### Fixed

- Bad resource names for Grape::API objects in Grape 1.2.0 (#639)
- RestClient raising NoMethodError when response is `nil` (#636, #642) (@frsantos)
- Rack middleware inserted twice in some Rails applications (#641)

## [0.17.2] - 2018-11-23

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.1...v0.17.2

### Fixed

- Resque integration shutting down tracer when forking is disabled (#637)

## [0.17.1] - 2018-11-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.0...v0.17.1

### Fixed

- RestClient incorrect app type (#583) (@gaborszakacs)
- DelayedJob incorrect job name when used with ActiveJob (#605) (@agirlnamedsophia)

## [0.17.0] - 2018-10-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.16.1...v0.17.0

### Added

- [BETA] Span memory `allocations` attribute (#597) (@dasch)

### Changed

- Use Rack Env to update resource in Rails (#580) (@dasch)
- Expand support for Sidekiq to 3.5.4+ (#593)
- Expand support for mysql2 to 0.3.21+ (#578)

### Refactored

- Upgraded integrations to new API (#544)
- Encoding classes into modules (#598)

## [0.16.1] - 2018-10-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.16.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.16.0...v0.16.1

### Fixed

- Priority sampling response being mishandled (#591)
- HTTP open timeout to agent too long (#582)

## [0.16.0] - 2018-09-18

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.16.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.15.0...v0.16.0

### Added

- OpenTracing support (#517)
- `middleware` option for disabling Rails trace middleware. (#552)

## [0.15.0] - 2018-09-12

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.15.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.2...v0.15.0

### Added

- Rails 5.2 support (#535)
- Context propagation support for `Concurrent::Future` (#415, #496)

### Fixed

- Grape uninitialized constant TraceMiddleware (#525, #533) (@dim)
- Signed integer trace and span IDs being discarded in distributed traces (#530) (@alloy)

## [0.14.2] - 2018-08-23

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.1...v0.14.2

### Fixed

- Sampling priority from request headers not being used (#521)  

## [0.14.1] - 2018-08-21

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0...v0.14.1

### Changed

- Reduce verbosity of connection errors in log (#515)

### Fixed

- Sequel 'not a valid integration' error (#514, #516) (@steveh)

## [0.14.0] - 2018-08-14

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.2...v0.14.0

### Added

- RestClient integration (#422, #460)
- DelayedJob integration (#393 #444)
- Version information to integrations (#483)
- Tracer#active_root_span helper (#503)

### Changed

- Resque to flush traces when Job finishes instead of using SyncWriter (#474)
- ActiveRecord to allow configuring multiple databases (#451)
- Integrations configuration settings (#450, #452, #451)

### Fixed

- Context propagation for distributed traces when context is full (#502)
- Rake shutdown tracer after execution (#487) (@kissrobber)
- Deprecation warnings fired using Unicorn (#508)

## [0.14.0.rc1] - 2018-08-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0.rc1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0.beta2...v0.14.0.rc1

### Added

- RestClient integration (#422, #460)
- Tracer#active_root_span helper (#503)

### Fixed

- Context propagation for distributed traces when context is full (#502)

## [0.14.0.beta2] - 2018-07-25

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0.beta2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0.beta1...v0.14.0.beta2

### Fixed

- Rake shutdown tracer after execution (#487) @kissrobber

## [0.14.0.beta1] - 2018-07-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.1...v0.14.0.beta1

### Changed

- Resque to flush traces when Job finishes instead of using SyncWriter (#474)
- ActiveRecord to allow configuring multiple databases (#451)
- Integrations configuration settings (#450, #452, #451)

### Fixed

- Ruby warnings during tests (#499)
- Tests failing intermittently on Ruby 1.9.3 (#497)

### Added

- DelayedJob integration (#393 #444)
- Version information to integrations (#483)

## [0.13.2] - 2018-08-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.1...v0.13.2

### Fixed

- Context propagation for distributed traces when context is full (#502)

## [0.13.1] - 2018-07-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.0...v0.13.1

### Changed

- Configuration class variables don't lazy load (#477)
- Default tracer host `localhost` --> `127.0.0.1` (#466, #480) (@NobodysNightmare)

### Fixed

- Workers not shutting down quickly in some short running processes (#475)
- Missing documentation for mysql2 and Rails (#476, #488)
- Missing variable in rescue block (#481) (@kitop)
- Unclosed spans in ActiveSupport::Notifications with multithreading (#431, #478) (@senny)

## [0.13.0] - 2018-06-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.1...v0.13.0

### Added

- Sequel integration (supporting Ruby 2.0+) (#171, #367) (@randy-girard, @twe4ked, @palin)
- gRPC integration (supporting Ruby 2.2+) (#379, #403) (@Jared-Prime)
- ActiveModelSerializers integration (#340) (@sullimander)
- Excon integration (#211, #426) (@walterking, @jeffjo)
- Rake integration (supporting Ruby 2.0+, Rake 12.0+) (#409)
- Request queuing tracing to Rack (experimental) (#272)
- ActiveSupport::Notifications::Event helper for event tracing (#400)
- Request and response header tags to Rack (#389)
- Request and response header tags to Sinatra (#427, #375)
- MySQL2 integration (#453) (@jamiehodge)
- Sidekiq job delay tag (#443, #418) (@gottfrois)

### Fixed

- Elasticsearch quantization of ids (#458)
- MongoDB to allow quantization of collection name (#463)

### Refactored

- Hash quantization into core library (#410)
- MongoDB integration to use Hash quantization library (#463)

### Changed 

- Hash quantization truncates arrays with nested objects (#463) 

## [0.13.0.beta1] - 2018-05-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0...v0.13.0.beta1

### Added

- Sequel integration (supporting Ruby 2.0+) (#171, #367) (@randy-girard, @twe4ked, @palin)
- gRPC integration (supporting Ruby 2.2+) (#379, #403) (@Jared-Prime)
- ActiveModelSerializers integration (#340) (@sullimander)
- Excon integration (#211) (@walterking)
- Rake integration (supporting Ruby 2.0+, Rake 12.0+) (#409)
- Request queuing tracing to Rack (experimental) (#272)
- ActiveSupport::Notifications::Event helper for event tracing (#400)
- Request and response header tags to Rack (#389)

### Refactored

- Hash quantization into core library (#410)

## [0.12.1] - 2018-06-12

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0...v0.12.1

### Changed

- Cache configuration `Proxy` objects (#446)
- `freeze` more constant strings, to improve memory usage (#446)
 - `Utils#truncate` to use slightly less memory (#446)

### Fixed

- Net/HTTP integration not permitting `service_name` to be overridden. (#407, #430) (@undergroundwebdesigns)
- Block not being passed through Elasticsearch client initialization. (#421) (@shayonj)
- Devise raising `NoMethodError` when bad login attempts are made. (#419, #420) (@frsantos)
- AWS spans using wrong resource name (#374, #377) (@jfrancoist)
- ActionView `NoMethodError` on very long traces. (#445, #447) (@jvalanen)

### Refactored

- ActionController patching strategy using modules. (#439)
- ActionView tracing strategy. (#445, #447)

## [0.12.0] - 2018-05-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.4...v0.12.0

### Added

- GraphQL integration (supporting graphql 1.7.9+) (#295)
- ActiveRecord object instantiation tracing (#311, #334)
- Subscriber module for ActiveSupport::Notifications tracing (#324, #380, #390, #395) (@dasch)
- HTTP quantization module (#384)
- Partial flushing option to tracer (#247, #397)

### Changed

- Rack applies URL quantization by default (#371)
- Elasticsearch applies body quantization by default (#362)
- Context for a single trace now has hard limit of 100,000 spans (#247)
- Tags with `rails.db.x` to `active_record.db.x` instead (#396)

### Fixed

- Loading the ddtrace library after Rails has fully initialized can result in load errors. (#357)
- Some scenarios where `middleware_names` could result in bad resource names (#354)
- ActionController instrumentation conflicting with some gems that monkey patch Rails (#391)

### Deprecated

- Use of `:datadog_rack_request_span` variable in favor of `'datadog.rack_request_span'` in Rack. (#365, #392)

### Refactored

- Racecar to use ActiveSupport::Notifications Subscriber module (#381)
- Rails to use ActiveRecord integration instead of its own implementation (#396)
- ActiveRecord to use ActiveSupport::Notifications Subscriber module (#396)

## [0.12.0.rc1] - 2018-04-11

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0.rc1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.4...v0.12.0.rc1

### Added

- GraphQL integration (supporting graphql 1.7.9+) (#295)
- ActiveRecord object instantiation tracing (#311, #334)
- Subscriber module for ActiveSupport::Notifications tracing (#324, #380, #390, #395) (@dasch)
- HTTP quantization module (#384)
- Partial flushing option to tracer (#247, #397)

### Changed

- Rack applies URL quantization by default (#371)
- Elasticsearch applies body quantization by default (#362)
- Context for a single trace now has hard limit of 100,000 spans (#247)
- Tags with `rails.db.x` to `active_record.db.x` instead (#396)

### Fixed

- Loading the ddtrace library after Rails has fully initialized can result in load errors. (#357)
- Some scenarios where `middleware_names` could result in bad resource names (#354)
- ActionController instrumentation conflicting with some gems that monkey patch Rails (#391)

### Deprecated

- Use of `:datadog_rack_request_span` variable in favor of `'datadog.rack_request_span'` in Rack. (#365, #392)

### Refactored

- Racecar to use ActiveSupport::Notifications Subscriber module (#381)
- Rails to use ActiveRecord integration instead of its own implementation (#396)
- ActiveRecord to use ActiveSupport::Notifications Subscriber module (#396)

## [0.12.0.beta2] - 2018-02-28

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0.beta2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0.beta1...v0.12.0.beta2

### Fixed

- Loading the ddtrace library after Rails has fully initialized can result in load errors. (#357)

## [0.12.0.beta1] - 2018-02-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.2...v0.12.0.beta1

### Added

- GraphQL integration (supporting graphql 1.7.9+) (#295)
- ActiveRecord object instantiation tracing (#311, #334)
- `http.request_id` tag to Rack spans (#335)

## [0.11.4] - 2018-03-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.4

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.3...v0.11.4

### Fixed

- Transport body parsing when downgrading (#369)
- Transport incorrectly attempting to apply sampling to service metadata (#370)
- `sql.active_record` traces showing incorrect adapter settings when non-default adapter used (#383)

## [0.11.3] - 2018-03-06

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.2...v0.11.3

### Added

- CHANGELOG.md (#350, #363) (@awendt)
- `http.request_id` tag to Rack spans (#335)
- Tracer configuration to README.md (#332) (@noma4i)

### Fixed

- Extra indentation in README.md (#349) (@ck3g)
- `http.url` when Rails raises exceptions (#351, #353)
- Rails from being patched twice (#352)
- 4XX responses from middleware being marked as errors (#345)
- Rails exception middleware sometimes not being inserted at correct position (#345)
- Processing pipeline documentation typo (#355) (@MMartyn)
- Loading the ddtrace library after Rails has fully initialized can result in load errors. (#357)
- Use of block syntax with Rails `render` not working (#359, #360) (@dorner)

## [0.11.2] - 2018-02-02

**Critical update**: `Datadog::Monkey` removed in version 0.11.1. Adds `Datadog::Monkey` back as no-op, deprecated module.

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.1...v0.11.2

### Deprecated

- `Datadog::Monkey` to be no-op and print deprecation warnings.

## [0.11.1] - 2018-01-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.0...v0.11.1

### Added

- `http.base_url` tag for Rack applications (#301, #327)
- `distributed_tracing` option to Sinatra (#325)
- `exception_controller` option to Rails (#320)

### Changed

- Decoupled Sinatra and ActiveRecord integrations (#328, #330) (@hawknewton)
- Racecar uses preferred ActiveSupport::Notifications strategy (#323)

### Removed

- `Datadog::Monkey` in favor of newer configuration API (#322)

### Fixed

- Custom resource names from Rails controllers being overridden (#321)
- Custom Rails exception controllers reporting as the resource (#320)

## [0.11.0] - 2018-01-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.10.0...v0.11.0

## [0.11.0.beta2] - 2017-12-27

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0.beta2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.0.beta1...v0.11.0.beta2

## [0.11.0.beta1] - 2017-12-04

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.10.0...v0.11.0.beta1

## [0.10.0] - 2017-11-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.10.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.9.2...v0.10.0

## [0.9.2] - 2017-11-03

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.9.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.9.1...v0.9.2

## [0.9.1] - 2017-11-02

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.9.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.9.0...v0.9.1

## [0.9.0] - 2017-10-06

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.9.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.8.2...v0.9.0

## [0.8.2] - 2017-09-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.8.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.8.1...v0.8.2

## [0.8.1] - 2017-08-10

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.8.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.8.0...v0.8.1

## [0.8.0] - 2017-07-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.8.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.7.2...v0.8.0

## [0.7.2] - 2017-05-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.7.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.7.1...v0.7.2

## [0.7.1] - 2017-05-10

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.7.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.7.0...v0.7.1

## [0.7.0] - 2017-04-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.7.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.6.2...v0.7.0

## [0.6.2] - 2017-04-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.6.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.6.1...v0.6.2

## [0.6.1] - 2017-04-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.6.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.6.0...v0.6.1

## [0.6.0] - 2017-03-28

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.6.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.5.0...v0.6.0

## [0.5.0] - 2017-03-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.5.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.4.3...v0.5.0

## [0.4.3] - 2017-02-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.4.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.4.2...v0.4.3

## [0.4.2] - 2017-02-14

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.4.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.4.1...v0.4.2

## [0.4.1] - 2017-02-14

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.4.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.4.0...v0.4.1

## [0.4.0] - 2017-01-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.4.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.3.1...v0.4.0

## [0.3.1] - 2017-01-23

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.3.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.3.0...v0.3.1

[Unreleased]: https://github.com/DataDog/dd-trace-rb/compare/v0.41.0...master
[0.43.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.42.0...v0.43.0
[0.41.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.40.0...v0.41.0
[0.40.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.39.0...v0.40.0
[0.39.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.38.0...v0.39.0
[0.38.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.37.0...v0.38.0
[0.37.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.36.0...v0.37.0
[0.36.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.35.2...v0.36.0
[0.35.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.35.1...v0.35.2
[0.35.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.35.0...v0.35.1
[0.35.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.34.2...v0.35.0
[0.34.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.34.1...v0.34.2
[0.34.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.34.0...v0.34.1
[0.34.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.33.1...v0.34.0
[0.33.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.33.0...v0.33.1
[0.33.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.31.1...v0.32.0
[0.31.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.31.0...v0.31.1
[0.31.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.30.1...v0.31.0
[0.30.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.30.0...v0.30.1
[0.30.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.29.1...v0.30.0
[0.29.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.29.0...v0.29.1
[0.29.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.28.0...v0.29.0
[0.28.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.27.0...v0.28.0
[0.27.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.26.0...v0.27.0
[0.26.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.25.1...v0.26.0
[0.25.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.24.0...v0.25.0
[0.24.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.23.3...v0.24.0
[0.23.3]: https://github.com/DataDog/dd-trace-rb/compare/v0.23.2...v0.23.3
[0.23.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.21.2...v0.22.0
[0.21.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.21.1...v0.21.2
[0.21.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.21.0...v0.21.1
[0.21.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.19.1...v0.20.0
[0.19.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.19.0...v0.19.1
[0.19.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.18.3...v0.19.0
[0.18.3]: https://github.com/DataDog/dd-trace-rb/compare/v0.18.2...v0.18.3
[0.18.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.18.1...v0.18.2
[0.18.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.17.3...v0.18.0
[0.17.3]: https://github.com/DataDog/dd-trace-rb/compare/v0.17.2...v0.17.3
[0.17.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.17.1...v0.17.2
[0.17.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.17.0...v0.17.1
[0.17.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.16.1...v0.17.0
[0.16.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.16.0...v0.16.1
[0.16.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.14.2...v0.15.0
[0.14.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.14.1...v0.14.2
[0.14.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0...v0.14.1
[0.14.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.13.2...v0.14.0
[0.14.0.rc1]: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0.beta2...v0.14.0.rc1
[0.14.0.beta2]: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0.beta1...v0.14.0.beta2
[0.14.0.beta1]: https://github.com/DataDog/dd-trace-rb/compare/v0.13.0...v0.14.0.beta1
[0.13.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.13.1...v0.13.2
[0.13.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.12.1...v0.13.0
[0.13.0.beta1]: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0...v0.13.0.beta1
[0.12.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.4...v0.12.0
[0.12.0.rc1]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.4...v0.12.0.rc1
[0.12.0.beta2]: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0.beta1...v0.12.0.beta2
[0.12.0.beta1]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.2...v0.12.0.beta1
[0.11.4]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.3...v0.11.4
[0.11.3]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.2...v0.11.3
[0.11.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.1...v0.11.2
[0.11.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.0...v0.11.1
[0.11.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.10.0...v0.11.0
[0.11.0.beta2]: https://github.com/DataDog/dd-trace-rb/compare/v0.11.0.beta1...v0.11.0.beta2
[0.11.0.beta1]: https://github.com/DataDog/dd-trace-rb/compare/v0.10.0...v0.11.0.beta1
[0.10.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.9.2...v0.10.0
[0.9.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.9.1...v0.9.2
[0.9.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.8.2...v0.9.0
[0.8.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.8.1...v0.8.2
[0.8.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.6.2...v0.7.0
[0.6.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.6.1...v0.6.2
[0.6.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/DataDog/dd-trace-rb/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/DataDog/dd-trace-rb/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/DataDog/dd-trace-rb/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/DataDog/dd-trace-rb/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/DataDog/dd-trace-rb/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/DataDog/dd-trace-rb/compare/v0.1.0...v0.1.1
