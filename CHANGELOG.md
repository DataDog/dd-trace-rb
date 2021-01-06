# Changelog

## [Unreleased]

## [0.44.0] - 2021-01-06

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.44.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.43.0...v0.44.0

### Added

- Ruby 3.0 support ([#1281][], [#1296][], [#1298][])
- Rails 6.1 support ([#1295][])
- Qless integration ([#1237][]) ([@sco11morgan][])
- AWS Textract service to AWS integration ([#1270][]) ([@Sticksword][])
- Ability to disable Redis argument capture ([#1276][]) ([@callumj][])
- Upload coverage report to Codecov ([#1289][])

### Changed

- Reduce Runtime Metrics frequency to every 10 seconds ([#1269][])

### Fixed

- Disambiguate resource names for Grape endpoints with shared paths ([#1279][]) ([@pzaich][])
- Remove invalid Jenkins URL from CI integration ([#1283][])

### Refactored

- Reduce memory allocation when unnecessary ([#1273][], [#1275][]) ([@callumj][])
- Improvements to test suite & CI ([#847][], [#1256][], [#1257][], [#1266][], [#1272][], [#1277][], [#1278][], [#1284][], [#1286][], [#1287][], [#1293][], [#1299][])
- Improvements to documentation ([#1262][], [#1263][], [#1264][], [#1267][], [#1268][], [#1297][])

## [0.43.0] - 2020-11-18

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.43.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.42.0...v0.43.0

### Added

- Background job custom error handlers ([#1212][]) ([@norbertnytko][])
- Add "multi" methods instrumentation for Rails cache ([#1217][]) ([@michaelkl][])
- Support custom error status codes for Grape ([#1238][])
- Cucumber integration ([#1216][])
- RSpec integration ([#1234][])
- Validation to `:on_error` argument on `Datadog::Tracer#trace` ([#1220][])

### Changed

- Update `TokenBucket#effective_rate` calculation ([#1236][])

### Fixed

- Avoid writer reinitialization during shutdown ([#1235][], [#1248][])
- Fix configuration multiplexing ([#1204][], [#1227][])
- Fix misnamed B3 distributed headers ([#1226][], [#1229][])
- Correct span type for AWS SDK ([#1233][])
- Correct span type for internal Pin on HTTP clients ([#1239][])
- Reset trace context after fork ([#1225][])

### Refactored

- Improvements to test suite ([#1232][], [#1244][])
- Improvements to documentation ([#1243][], [#1218][]) ([@cjford][])

### Removed

## [0.42.0] - 2020-10-21

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.42.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.41.0...v0.42.0

### Added

- Increase Resque support to include 2.0  ([#1213][]) ([@erict-square][])

- Improve gRPC Propagator to support metadata array values ([#1203][]) ([@mdehoog][])

- Add CPU benchmarks, diagnostics to tests ([#1188][], [#1198][])

- Access active correlation by Thread ([#1200][])

- Improve delayed_job instrumentation ([#1187][]) ([@norbertnytko][])

### Changed

### Fixed

- Improve Rails `log_injection` option to support more Lograge formats ([#1210][]) ([@Supy][])

- Fix Changelog ([#1199][]) ([@y-yagi][])

### Refactored

- Refactor Trace buffer into multiple components ([#1195][])

## [0.41.0] - 2020-09-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.41.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.40.0...v0.41.0

### Added

- Improve duration counting using monotonic clock ([#424][], [#1173][]) ([@soulcutter][])

### Changed

- Add peer.service tag to external services and skip tagging external services with language tag for runtime metrics ([#934][], [#935][], [#1180][])
  - This helps support the way runtime metrics are associated with spans in the UI.
- Faster TraceBuffer for CRuby ([#1172][])
- Reduce memory usage during gem startup ([#1090][])
- Reduce memory usage of the HTTP transport ([#1165][])

### Fixed

- Improved prepared statement support for Sequel  integrations ([#1186][])
- Fix Sequel instrumentation when executing literal strings ([#1185][]) ([@matchbookmac][])
- Remove explicit `Logger` class verification ([#1181][]) ([@bartekbsh][])
  - This allows users to pass in a custom logger that does not inherit from `Logger` class.
- Correct tracer buffer metric counting ([#1182][])
- Fix Span#pretty_print for empty duration ([#1183][])

### Refactored

- Improvements to test suite & CI ([#1179][], [#1184][], [#1177][], [#1178][], [#1176][])
- Reduce generated Span ID range to fit in Fixnum ([#1189][])

## [0.40.0] - 2020-09-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.40.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.39.0...v0.40.0

### Added

- Rails `log_injection` option to auto enable log correlation ([#1157][])
- Que integration ([#1141][], [#1146][]) ([@hs-bguven][])
- `Components#startup!` hook ([#1151][])
- Code coverage report ([#1159][])
  - Every commit now has a `coverage` CI step that contains the code coverage report. This report can be found in the `Artifacts` tab of that CI step, under `coverage/index.html`.

### Changed

- Use a single top level span for Racecar consumers ([#1150][]) ([@dasch][])

### Fixed

- Sinatra nested modular applications possibly leaking spans ([#1035][], [#1145][])
  
  * **BREAKING** for nested modular Sinatra applications only:
    ```ruby
    class Nested < Sinatra::Base
    end
    
    class TopLevel < Sinatra::Base
      use Nested # Nesting happens here
    end
    ```
  * Non-breaking for classic applications nor modular non-nested applications.
  
  Fixes issues introduced by [#1015][] (in 0.35.0), when we first introduced Sinatra support for modular applications.
  
  The main issue we had to solve for modular support is how to handle nested applications, as only one application is actually responsible for handling the route. A naive implementation would cause the creation of nested `sinatra.request` spans, even for applications that did not handle the request. This is technically correct, as Sinatra is traversing that middleware, accruing overhead, but that does not aligned with our existing behavior of having a single `sinatra.request` span.
  
  While trying to achieve backwards-compatibility, we had to resort to a solution that turned out brittle: `sinatra.request` spans had to start in one middleware level and finished it in another. This allowed us to only capture the `sinatra.request` for the matching route, and skip the non-matching one. This caused unexpected issues on some user setups, specially around Sinatra middleware that created spans in between the initialization and closure of `sinatra.request` spans.
  
  This change now address these implementation issues by creating multiple `sinatra.request`, one for each traversed Sinatra application, even non-matching ones. This instrumentation is more correct, but at the cost of being a breaking change for nested modular applications.
  
  Please see [#1145][] for more information, and example screenshots on how traces for affected applications will look like.

- Rack/Rails span error propagation with `rescue_from` ([#1155][], [#1162][])
- Prevent logger recursion during startup ([#1158][])
- Race condition on new worker classes ([#1154][])
  - These classes represent future work, and not being used at the moment.

### Refactored

- Run CI tests in parallel ([#1156][])
- Migrate minitest tests to RSpec ([#1127][], [#1128][], [#1133][], [#1149][], [#1152][], [#1153][])
- Improvements to test suite ([#1134][], [#1148][], [#1163][])
- Improvements to documentation ([#1138][])

### Removed

- **Ruby 1.9 support ended, as it transitions from Maintenance to End-Of-Life ([#1137][])**
- GitLab status check when not applicable ([#1160][])
  - Allows for PRs pass all status checks once again. Before this change, a `dd-gitlab/copy_to_s3` check would never leave the "Pending" status. This check tracks the deployment of a commit to an internal testing platform, which currently only happens on `master` branch or when manually triggered internally.

## [0.39.0] - 2020-08-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.39.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.38.0...v0.39.0

### Added

- JRuby 9.2 support ([#1126][])
- Sneakers integration ([#1121][]) ([@janz93][])

### Changed

- Consistent environment variables across languages ([#1115][])
- Default logger level from WARN to INFO ([#1120][]) ([@gingerlime][])
  - This change also reduces the startup environment log message to INFO level ([#1104][])

### Fixed

- HTTP::StateError on error responses for http.rb ([#1116][], [#1122][]) ([@evan-waters][])
- Startup log error when using the test adapter ([#1125][], [#1131][]) ([@benhutton][])
- Warning message for Faraday < 1.0 ([#1129][]) ([@fledman][], [@tjwp][])
- Propagate Rails error message to Rack span ([#1124][])

### Refactored

- Improved ActiveRecord documentation ([#1119][])
- Improvements to test suite ([#1105][], [#1118][])

## [0.38.0] - 2020-07-13

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.38.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.37.0...v0.38.0

### Added

- http.rb integration ([#529][], [#853][])
- Kafka integration ([#1070][]) ([@tjwp][])
- Span#set_tags ([#1081][]) ([@DocX][])
- retry_count tag for Sidekiq jobs ([#1089][]) ([@elyalvarado][])
- Startup environment log ([#1104][], [#1109][])
- DD_SITE and DD_API_KEY configuration ([#1107][])

### Changed

- Auto instrument Faraday default connection ([#1057][])
- Sidekiq client middleware is now the same for client and server ([#1099][]) ([@drcapulet][])
- Single pass SpanFilter ([#1071][]) ([@tjwp][])

### Fixed

- Ensure fatal exceptions are propagated ([#1100][])
- Respect child_of: option in Tracer#trace ([#1082][]) ([@DocX][])
- Improve Writer thread safety ([#1091][]) ([@fledman][])

### Refactored

- Improvements to test suite ([#1092][], [#1103][])

## [0.37.0] - 2020-06-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.37.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.36.0...v0.37.0

### Refactored

- Documentation improvements regarding Datadog Agent defaults ([#1074][]) ([@cswatt][])
- Improvements to test suite ([#1043][], [#1051][], [#1062][], [#1075][], [#1076][], [#1086][])

### Removed

- **DEPRECATION**: Deprecate Contrib::Configuration::Settings#tracer= ([#1072][], [#1079][])
  - The `tracer:` option is no longer supported for integration configuration. A deprecation warning will be issued when this option is used.
  - Tracer instances are dynamically created when `ddtrace` is reconfigured (through `Datadog.configure{}` calls).

    A reference to a tracer instance cannot be stored as it will be replaced by a new instance during reconfiguration.

    Retrieving the global tracer instance, by invoking `Datadog.tracer`, is the only safe mechanism to acquire the active tracer instance.

    Allowing an integration to set its tracer instance is effectively preventing that integration from dynamically retrieving the current active tracer in the future, thus causing it to record spans in a stale tracer instance. Spans recorded in a stale tracer instance will look disconnected from their parent context.

- **BREAKING**: Remove Pin#tracer= and DeprecatedPin#tracer= ([#1073][])
  - The `Pin` and `DeprecatedPin` are internal tools used to provide more granular configuration for integrations.
  - The APIs being removed are not public nor have been externally documented. The `DeprecatedPin` specifically has been considered deprecated since 0.20.0.
  - This removal is a continuation of [#1079][] above, thus carrying the same rationale.

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

- Prevent trace components from being re-initialized multiple times during setup ([#1037][])

### Fixed

- Allow Rails patching if Railties are loaded ([#993][], [#1054][]) ([@mustela][], [@bheemreddy181][], [@vramaiah][])
- Pin delegates to default tracer unless configured ([#1041][])

### Refactored

- Improvements to test suite ([#1027][], [#1031][], [#1045][], [#1046][], [#1047][])

## [0.35.2] - 2020-05-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.35.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.35.1...v0.35.2

### Fixed

- Internal tracer HTTP requests generating traces ([#1030][], [#1033][]) ([@gingerlime][])
- `Datadog.configure` forcing all options to eager load ([#1032][], [#1034][]) ([@kelvin-acosta][])

## [0.35.1] - 2020-05-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.35.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.35.0...v0.35.1

### Fixed

- Components#teardown! NoMethodError ([#1021][], [#1023][]) ([@bzf][])

## [0.35.0] - 2020-04-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.35.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.34.2...v0.35.0

### Added

- Chunk large trace payloads before flushing ([#818][], [#840][])
- Support for Sinatra modular apps ([#486][], [#913][], [#1015][]) ([@jpaulgs][], [@tomasv][], [@ZimbiX][])
- active_job support for Resque ([#991][]) ([@stefanahman][], [@psycholein][])
- JRuby 9.2 to CI test matrix ([#995][])
- `TraceWriter` and `AsyncTraceWriter` workers ([#986][])
- Runtime metrics worker ([#988][])

### Changed

- Populate env, service, and version from tags ([#1008][])
- Extract components from configuration ([#996][])
- Extract logger to components ([#997][])
- Extract runtime metrics worker from `Writer` ([#1004][])
- Improvements to Faraday documentation ([#1005][])

### Fixed

- Runtime metrics not starting after #write ([#1010][])

### Refactored

- Improvements to test suite ([#842][], [#1006][], [#1009][])

## [0.34.2] - 2020-04-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.34.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.34.1...v0.34.2

### Changed

- Revert Rails applications setting default `env` if none are configured. ([#1000][]) ([@errriclee][])

## [0.34.1] - 2020-04-02

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.34.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.34.0...v0.34.1

### Changed

- Rails applications set default `service` and `env` if none are configured. ([#990][])

### Fixed

- Some configuration settings not applying ([#989][], [#990][]) ([@rahul342][])

## [0.34.0] - 2020-03-31

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.34.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.33.1...v0.34.0

### Added

- `Datadog::Event` for simple pub-sub messaging ([#972][])
- `Datadog::Workers` for trace writing ([#969][], [#973][])
- `_dd.measured` tag to some integrations for more statistics ([#974][])
- `env`, `service`, `version`, `tags` configuration for auto-tagging ([#977][], [#980][], [#982][], [#983][], [#985][])
- Multiplexed configuration for Ethon, Excon, Faraday, HTTP integrations ([#882][], [#953][]) ([@stormsilver][])

### Fixed

- Runtime metrics configuration dropping with new writer ([#967][], [#968][]) ([@ericmustin][])
- Faraday "unexpected middleware" warnings on v0.x ([#965][], [#971][])
- Presto configuration ([#975][])
- Test suite issues ([#981][])

## [0.33.1] - 2020-03-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.33.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.33.0...v0.33.1

### Fixed

- NoMethodError when activating instrumentation for non-existent library ([#964][], [#966][]) ([@roccoblues][], [@brafales][])

## [0.33.0] - 2020-03-05

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.33.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.32.0...v0.33.0

### Added

- Instrumentation for [Presto](https://github.com/treasure-data/presto-client-ruby) ([#775][], [#920][], [#961][]) ([@ahammel][], [@ericmustin][])
- Sidekiq job argument tagging ([#933][]) ([@mantrala][])
- Support for multiple Redis services ([#861][], [#937][], [#940][]) ([@mberlanda][])
- Support for Sidekiq w/ Delayed extensions ([#798][], [#942][]) ([@joeyAghion][])
- Setter/reset behavior for configuration options ([#957][])
- Priority sampling rate tag ([#891][])

### Changed

- Enforced minimum version requirements for instrumentation ([#944][])
- RubyGems minimum version requirement 2.0.0 ([#954][]) ([@Joas1988][])
- Relaxed Rack minimum version to 1.1.0 ([#952][])

### Fixed

- AWS instrumentation patching when AWS is partially loaded ([#938][], [#945][]) ([@letiesperon][], [@illdelph][])
- NoMethodError for RuleSampler with priority sampling ([#949][], [#950][]) ([@BabyGroot][])
- Runtime metrics accumulating service names when disabled ([#956][])
- Sidekiq instrumentation incompatibility with Rails 6.0.2 ([#943][], [#947][]) ([@pj0tr][])
- Documentation tweaks ([#948][], [#955][]) ([@mstruve][], [@link04][])
- Various test suite issues ([#930][], [#932][], [#951][], [#960][])

## [0.32.0] - 2020-01-22

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.32.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.31.1...v0.32.0

### Added

- New transport: Datadog::Transport::IO ([#910][])
- Dual License ([#893][], [#921][])

### Changed

- Improved annotation of `net/http` spans during exception ([#888][], [#907][]) ([@djmb][], [@ericmustin][])
- RuleSampler is now the default sampler; no behavior changes by default ([#917][])

### Refactored

- Improved support for multiple tracer instances ([#919][])
- Improvements to test suite ([#909][], [#928][], [#929][])

## [0.31.1] - 2020-01-15

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.31.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.31.0...v0.31.1

### Fixed

- Implement SyncWriter#stop method ([#914][], [#915][]) ([@Yurokle][])
- Fix references to Datadog::Tracer.log ([#912][])
- Ensure http.status_code tag is always a string ([#927][])

### Refactored

- Improvements to test suite & CI ([#911][], [#918][])

## [0.31.0] - 2020-01-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.31.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.30.1...v0.31.0

### Added

- Ruby 2.7 support ([#805][], [#896][])
- ActionCable integration ([#132][], [#824][]) ([@renchap][], [@ericmustin][])
- Faraday 1.0 support ([#906][])
- Set resource for Rails template spans ([#855][], [#881][]) ([@djmb][])
- at_exit hook for graceful Tracer shutdown ([#884][])
- Environment variables to configure RuleSampler defaults ([#892][])

### Changed

- Updated partial trace flushing to conform with new back-end requirements ([#845][])
- Store numeric tags as metrics ([#886][])
- Moved logging from Datadog::Tracer to Datadog::Logger ([#880][])
- Changed default RuleSampler rate limit from unlimited to 100/s ([#898][])

### Fixed

- SyncWriter incompatibility with Transport::HTTP::Client ([#903][], [#904][]) ([@Yurokle][])

### Refactored

- Improvements to test suite & CI ([#815][], [#821][], [#841][], [#846][], [#883][], [#895][])

## [0.30.1] - 2019-12-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.30.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.30.0...v0.30.1

### Fixed

- NoMethodError when configuring tracer with SyncWriter ([#899][], [#900][]) ([@Yurokle][])
- Spans associated with runtime metrics when disabled ([#885][])

### Refactored

- Improvements to test suite & CI ([#815][], [#821][], [#846][], [#883][], [#890][], [#894][])

## [0.30.0] - 2019-12-04

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.30.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.29.1...v0.30.0

### Added

- Additional tracer health metrics ([#867][])
- Integration patching instrumentation ([#871][])
- Rule-based trace sampling ([#854][])

### Fixed

- Rails template layout name error ([#872][]) ([@djmb][])

## [0.29.1] - 2019-11-26

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.29.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.29.0...v0.29.1

### Fixed

- Priority sampling not activating by default ([#868][])

## [0.29.0] - 2019-11-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.29.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.28.0...v0.29.0

### Added

- Tracer health metrics ([#838][], [#859][])

### Changed

- Default trace buffer size from 100 to 1000 ([#865][])
- Rack request start headers to accept more values ([#832][]) ([@JamesHarker][])
- Faraday to apply default instrumentation out-of-the-box ([#786][], [#843][]) ([@mdross95][])

### Fixed

- Synthetics trace context being ignored ([#856][])

### Refactored

- Tracer buffer constants ([#851][])

### Removed

- Some old Ruby 1.9 code ([#819][], [#844][])

## [0.28.0] - 2019-10-01

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.28.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.27.0...v0.28.0

### Added

- Support for Rails 6.0 ([#814][])
- Multiplexing on hostname/port for Dalli ([#823][])
- Support for Redis array arguments ([#796][], [#817][]) ([@brafales][])

### Refactored

- Encapsulate span resource name in Faraday integration ([#811][]) ([@giancarlocosta][])

## [0.27.0] - 2019-09-04

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.27.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.26.0...v0.27.0

Support for Ruby < 2.0 is *removed*. Plan for timeline is as follows:

 - 0.25.0: Support for Ruby < 2.0 is deprecated; retains full feature support.
 - 0.26.0: Last version to support Ruby < 2.0; any new features will not support 1.9.
 - 0.27.0: Support for Ruby < 2.0 is removed.

Version 0.26.x will receive only critical bugfixes for 1 year following the release of 0.26.0 (August 6th, 2020.)

### Added

- Support for Ruby 2.5 & 2.6 ([#800][], [#802][])
- Ethon integration ([#527][], [#778][]) ([@al-kudryavtsev][])

### Refactored

- Rails integration into smaller integrations per component ([#747][], [#762][], [#795][])

### Removed

- Support for Ruby 1.9 ([#791][])

## [0.26.0] - 2019-08-06

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.26.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.25.1...v0.26.0

Support for Ruby < 2.0 is *deprecated*. Plan for timeline is as follows:

 - 0.25.0: Support for Ruby < 2.0 is deprecated; retains full feature support.
 - 0.26.0: Last version to support Ruby < 2.0; any new features will not support 1.9.
 - 0.27.0: Support for Ruby < 2.0 is removed.

Version 0.26.x will receive only critical bugfixes for 1 year following the release of 0.26.0 (August 6th, 2020.)

### Added

- Container ID tagging for containerized environments ([#784][])

### Refactored

- Datadog::Metrics constants ([#789][])

### Removed

- Datadog::HTTPTransport and related components ([#782][])

## [0.25.1] - 2019-07-16

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.25.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.25.0...v0.25.1

### Fixed

- Redis integration not quantizing AUTH command ([#776][])

## [0.25.0] - 2019-06-27

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.25.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.24.0...v0.25.0

Support for Ruby < 2.0 is *deprecated*. Plan for timeline is as follows:

 - 0.25.0: Support for Ruby < 2.0 is deprecated; retains full feature support.
 - 0.26.0: Last version to support Ruby < 2.0; any new features will not support 1.9.
 - 0.27.0: Support for Ruby < 2.0 is removed.

Version 0.26.x will receive only critical bugfixes for 1 year following the release of 0.26.0.

### Added

- Unix socket support for transport layer ([#770][])

### Changed

- Renamed 'ForcedTracing' to 'ManualTracing' ([#765][])

### Fixed

- HTTP headers for distributed tracing sometimes appearing in duplicate ([#768][])

### Refactored

- Transport layer ([#628][])

### Deprecated

- Ruby < 2.0 support ([#771][])
- Use of `Datadog::HTTPTransport` ([#628][])
- Use of `Datadog::Ext::ForcedTracing` ([#765][])

## [0.24.0] - 2019-05-21

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.24.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.3...v0.24.0

### Added

- B3 header support ([#753][])
- Hostname tagging option ([#760][])
- Contribution and development guides ([#754][])

## [0.23.3] - 2019-05-16

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.2...v0.23.3

### Fixed

- Integrations initializing tracer at load time ([#756][])

## [0.23.2] - 2019-05-10

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.1...v0.23.2

### Fixed

- Span types for HTTP, web, and some datastore integrations ([#751][])
- AWS integration not patching service-level gems ([#707][], [#752][]) ([@alksl][], [@tonypinder][])
- Rails 6 warning for `parent_name` ([#750][]) ([@sinsoku][])

## [0.23.1] - 2019-05-02

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.23.0...v0.23.1

### Fixed

- NoMethodError runtime_metrics for SyncWriter ([#748][])

## [0.23.0] - 2019-04-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.23.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.22.0...v0.23.0

### Added

- Error status support via tags for OpenTracing ([#739][])
- Forced sampling support via tags ([#720][])

### Fixed

- Wrong return values for Rake integration ([#742][]) ([@Redapted][])

### Removed

- Obsolete service telemetry ([#738][])

## [0.22.0] - 2019-04-15

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.22.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.21.2...v0.22.0

In this release we are adding initial support for the **beta** [Runtime metrics collection](https://docs.datadoghq.com/tracing/advanced/runtime_metrics/?tab=ruby) feature.

### Changed

- Add warning log if an integration is incompatible ([#722][]) ([@ericmustin][])

### Added

- Initial beta support for Runtime metrics collection ([#677][])

## [0.21.2] - 2019-04-10

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.21.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.21.1...v0.21.2

### Changed

- Support Mongo gem 2.5+ ([#729][], [#731][]) ([@ricbartm][])

## [0.21.1] - 2019-03-26

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.21.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.21.0...v0.21.1

### Changed

- Support `TAG_ENABLED` for custom instrumentation with analytics. ([#728][])

## [0.21.0] - 2019-03-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.21.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.20.0...v0.21.0

### Added

- Trace analytics support ([#697][], [#715][])
- HTTP after_request span hook ([#716][], [#724][])

### Fixed

- Distributed traces with IDs in 2^64 range being dropped ([#719][])
- Custom logger level forced to warning ([#681][], [#721][]) ([@blaines][], [@ericmustin][])

### Refactored

- Global configuration for tracing into configuration API ([#714][])

## [0.20.0] - 2019-03-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.20.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.19.1...v0.20.0

This release will log deprecation warnings for any usage of `Datadog::Pin`.
These changes are backwards compatible, but all integration configuration should be moved away from `Pin` and to the configuration API instead.

### Added

- Propagate synthetics origin header ([#699][])

### Changed

- Enable distributed tracing by default ([#701][])

### Fixed

- Fix Rack http_server.queue spans missing from distributed traces ([#709][])

### Refactored

- Refactor MongoDB to use instrumentation module ([#704][])
- Refactor HTTP to use instrumentation module ([#703][])
- Deprecate GRPC global pin in favor of configuration API ([#702][])
- Deprecate Grape pin in favor of configuration API ([#700][])
- Deprecate Faraday pin in favor of configuration API ([#696][])
- Deprecate Dalli pin in favor of configuration API ([#693][])

## [0.19.1] - 2019-02-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.19.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.19.0...v0.19.1

### Added

- Documentation for Lograge implementation ([#683][], [#687][]) ([@nic-lan][])

### Fixed

- Priority sampling dropping spans ([#686][])

## [0.19.0] - 2019-01-22

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.19.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.3...v0.19.0

### Added

- Tracer#active_correlation for adding correlation IDs to logs. ([#660][], [#664][], [#673][])
- Opt-in support for `event_sample_rate` tag for some integrations. ([#665][], [#666][])

### Changed

- Priority sampling enabled by default. ([#654][])

## [0.18.3] - 2019-01-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.2...v0.18.3

### Fixed

- Mongo `NoMethodError` when no span available during `#failed`. ([#674][], [#675][]) ([@Azure7111][])
- Rack deprecation warnings firing with some 3rd party libraries present. ([#672][])
- Shoryuken resource name when used with ActiveJob. ([#671][]) ([@aurelian][])

## [0.18.2] - 2019-01-03

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.1...v0.18.2

### Fixed

- Unfinished Mongo spans when SASL configured ([#658][]) ([@zachmccormick][])
- Possible performance issue with unexpanded Rails cache keys ([#630][], [#635][]) ([@gingerlime][])

## [0.18.1] - 2018-12-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.18.0...v0.18.1

### Fixed

- ActiveRecord `SystemStackError` with some 3rd party libraries ([#661][], [#662][]) ([@EpiFouloux][], [@tjgrathwell][], [@guizmaii][])

## [0.18.0] - 2018-12-18

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.18.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.3...v0.18.0

### Added

- Shoryuken integration ([#538][], [#626][], [#655][]) ([@steveh][], [@JustSnow][])
- Sidekiq client integration ([#602][], [#650][]) ([@dirk][])
- Datadog::Shim for adding instrumentation ([#648][])

### Changed

- Use `DD_AGENT_HOST` and `DD_TRACE_AGENT_PORT` env vars if available ([#631][])
- Inject `:connection` into `sql.active_record` event ([#640][], [#649][], [#656][]) ([@guizmaii][])
- Return default configuration instead of `nil` on miss ([#651][])

## [0.17.3] - 2018-11-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.2...v0.17.3

### Fixed

- Bad resource names for Grape::API objects in Grape 1.2.0 ([#639][])
- RestClient raising NoMethodError when response is `nil` ([#636][], [#642][]) ([@frsantos][])
- Rack middleware inserted twice in some Rails applications ([#641][])

## [0.17.2] - 2018-11-23

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.1...v0.17.2

### Fixed

- Resque integration shutting down tracer when forking is disabled ([#637][])

## [0.17.1] - 2018-11-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.17.0...v0.17.1

### Fixed

- RestClient incorrect app type ([#583][]) ([@gaborszakacs][])
- DelayedJob incorrect job name when used with ActiveJob ([#605][]) ([@agirlnamedsophia][])

## [0.17.0] - 2018-10-30

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.17.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.16.1...v0.17.0

### Added

- [BETA] Span memory `allocations` attribute ([#597][]) ([@dasch][])

### Changed

- Use Rack Env to update resource in Rails ([#580][]) ([@dasch][])
- Expand support for Sidekiq to 3.5.4+ ([#593][])
- Expand support for mysql2 to 0.3.21+ ([#578][])

### Refactored

- Upgraded integrations to new API ([#544][])
- Encoding classes into modules ([#598][])

## [0.16.1] - 2018-10-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.16.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.16.0...v0.16.1

### Fixed

- Priority sampling response being mishandled ([#591][])
- HTTP open timeout to agent too long ([#582][])

## [0.16.0] - 2018-09-18

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.16.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.15.0...v0.16.0

### Added

- OpenTracing support ([#517][])
- `middleware` option for disabling Rails trace middleware. ([#552][])

## [0.15.0] - 2018-09-12

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.15.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.2...v0.15.0

### Added

- Rails 5.2 support ([#535][])
- Context propagation support for `Concurrent::Future` ([#415][], [#496][])

### Fixed

- Grape uninitialized constant TraceMiddleware ([#525][], [#533][]) ([@dim][])
- Signed integer trace and span IDs being discarded in distributed traces ([#530][]) ([@alloy][])

## [0.14.2] - 2018-08-23

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.1...v0.14.2

### Fixed

- Sampling priority from request headers not being used ([#521][])  

## [0.14.1] - 2018-08-21

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0...v0.14.1

### Changed

- Reduce verbosity of connection errors in log ([#515][])

### Fixed

- Sequel 'not a valid integration' error ([#514][], [#516][]) ([@steveh][])

## [0.14.0] - 2018-08-14

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.2...v0.14.0

### Added

- RestClient integration ([#422][], [#460][])
- DelayedJob integration ([#393][] [#444][])
- Version information to integrations ([#483][])
- Tracer#active_root_span helper ([#503][])

### Changed

- Resque to flush traces when Job finishes instead of using SyncWriter ([#474][])
- ActiveRecord to allow configuring multiple databases ([#451][])
- Integrations configuration settings ([#450][], [#452][], [#451][])

### Fixed

- Context propagation for distributed traces when context is full ([#502][])
- Rake shutdown tracer after execution ([#487][]) ([@kissrobber][])
- Deprecation warnings fired using Unicorn ([#508][])

## [0.14.0.rc1] - 2018-08-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0.rc1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0.beta2...v0.14.0.rc1

### Added

- RestClient integration ([#422][], [#460][])
- Tracer#active_root_span helper ([#503][])

### Fixed

- Context propagation for distributed traces when context is full ([#502][])

## [0.14.0.beta2] - 2018-07-25

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0.beta2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.14.0.beta1...v0.14.0.beta2

### Fixed

- Rake shutdown tracer after execution ([#487][]) [@kissrobber][]

## [0.14.0.beta1] - 2018-07-24

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.14.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.1...v0.14.0.beta1

### Changed

- Resque to flush traces when Job finishes instead of using SyncWriter ([#474][])
- ActiveRecord to allow configuring multiple databases ([#451][])
- Integrations configuration settings ([#450][], [#452][], [#451][])

### Fixed

- Ruby warnings during tests ([#499][])
- Tests failing intermittently on Ruby 1.9.3 ([#497][])

### Added

- DelayedJob integration ([#393][] [#444][])
- Version information to integrations ([#483][])

## [0.13.2] - 2018-08-07

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.1...v0.13.2

### Fixed

- Context propagation for distributed traces when context is full ([#502][])

## [0.13.1] - 2018-07-17

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.13.0...v0.13.1

### Changed

- Configuration class variables don't lazy load ([#477][])
- Default tracer host `localhost` --> `127.0.0.1` ([#466][], [#480][]) ([@NobodysNightmare][])

### Fixed

- Workers not shutting down quickly in some short running processes ([#475][])
- Missing documentation for mysql2 and Rails ([#476][], [#488][])
- Missing variable in rescue block ([#481][]) ([@kitop][])
- Unclosed spans in ActiveSupport::Notifications with multithreading ([#431][], [#478][]) ([@senny][])

## [0.13.0] - 2018-06-20

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.1...v0.13.0

### Added

- Sequel integration (supporting Ruby 2.0+) ([#171][], [#367][]) ([@randy-girard][], [@twe4ked][], [@palin][])
- gRPC integration (supporting Ruby 2.2+) ([#379][], [#403][]) ([@Jared-Prime][])
- ActiveModelSerializers integration ([#340][]) ([@sullimander][])
- Excon integration ([#211][], [#426][]) ([@walterking][], [@jeffjo][])
- Rake integration (supporting Ruby 2.0+, Rake 12.0+) ([#409][])
- Request queuing tracing to Rack (experimental) ([#272][])
- ActiveSupport::Notifications::Event helper for event tracing ([#400][])
- Request and response header tags to Rack ([#389][])
- Request and response header tags to Sinatra ([#427][], [#375][])
- MySQL2 integration ([#453][]) ([@jamiehodge][])
- Sidekiq job delay tag ([#443][], [#418][]) ([@gottfrois][])

### Fixed

- Elasticsearch quantization of ids ([#458][])
- MongoDB to allow quantization of collection name ([#463][])

### Refactored

- Hash quantization into core library ([#410][])
- MongoDB integration to use Hash quantization library ([#463][])

### Changed 

- Hash quantization truncates arrays with nested objects ([#463][]) 

## [0.13.0.beta1] - 2018-05-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.13.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0...v0.13.0.beta1

### Added

- Sequel integration (supporting Ruby 2.0+) ([#171][], [#367][]) ([@randy-girard][], [@twe4ked][], [@palin][])
- gRPC integration (supporting Ruby 2.2+) ([#379][], [#403][]) ([@Jared-Prime][])
- ActiveModelSerializers integration ([#340][]) ([@sullimander][])
- Excon integration ([#211][]) ([@walterking][])
- Rake integration (supporting Ruby 2.0+, Rake 12.0+) ([#409][])
- Request queuing tracing to Rack (experimental) ([#272][])
- ActiveSupport::Notifications::Event helper for event tracing ([#400][])
- Request and response header tags to Rack ([#389][])

### Refactored

- Hash quantization into core library ([#410][])

## [0.12.1] - 2018-06-12

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0...v0.12.1

### Changed

- Cache configuration `Proxy` objects ([#446][])
- `freeze` more constant strings, to improve memory usage ([#446][])
 - `Utils#truncate` to use slightly less memory ([#446][])

### Fixed

- Net/HTTP integration not permitting `service_name` to be overridden. ([#407][], [#430][]) ([@undergroundwebdesigns][])
- Block not being passed through Elasticsearch client initialization. ([#421][]) ([@shayonj][])
- Devise raising `NoMethodError` when bad login attempts are made. ([#419][], [#420][]) ([@frsantos][])
- AWS spans using wrong resource name ([#374][], [#377][]) ([@jfrancoist][])
- ActionView `NoMethodError` on very long traces. ([#445][], [#447][]) ([@jvalanen][])

### Refactored

- ActionController patching strategy using modules. ([#439][])
- ActionView tracing strategy. ([#445][], [#447][])

## [0.12.0] - 2018-05-08

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.4...v0.12.0

### Added

- GraphQL integration (supporting graphql 1.7.9+) ([#295][])
- ActiveRecord object instantiation tracing ([#311][], [#334][])
- Subscriber module for ActiveSupport::Notifications tracing ([#324][], [#380][], [#390][], [#395][]) ([@dasch][])
- HTTP quantization module ([#384][])
- Partial flushing option to tracer ([#247][], [#397][])

### Changed

- Rack applies URL quantization by default ([#371][])
- Elasticsearch applies body quantization by default ([#362][])
- Context for a single trace now has hard limit of 100,000 spans ([#247][])
- Tags with `rails.db.x` to `active_record.db.x` instead ([#396][])

### Fixed

- Loading the ddtrace library after Rails has fully initialized can result in load errors. ([#357][])
- Some scenarios where `middleware_names` could result in bad resource names ([#354][])
- ActionController instrumentation conflicting with some gems that monkey patch Rails ([#391][])

### Deprecated

- Use of `:datadog_rack_request_span` variable in favor of `'datadog.rack_request_span'` in Rack. ([#365][], [#392][])

### Refactored

- Racecar to use ActiveSupport::Notifications Subscriber module ([#381][])
- Rails to use ActiveRecord integration instead of its own implementation ([#396][])
- ActiveRecord to use ActiveSupport::Notifications Subscriber module ([#396][])

## [0.12.0.rc1] - 2018-04-11

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0.rc1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.4...v0.12.0.rc1

### Added

- GraphQL integration (supporting graphql 1.7.9+) ([#295][])
- ActiveRecord object instantiation tracing ([#311][], [#334][])
- Subscriber module for ActiveSupport::Notifications tracing ([#324][], [#380][], [#390][], [#395][]) ([@dasch][])
- HTTP quantization module ([#384][])
- Partial flushing option to tracer ([#247][], [#397][])

### Changed

- Rack applies URL quantization by default ([#371][])
- Elasticsearch applies body quantization by default ([#362][])
- Context for a single trace now has hard limit of 100,000 spans ([#247][])
- Tags with `rails.db.x` to `active_record.db.x` instead ([#396][])

### Fixed

- Loading the ddtrace library after Rails has fully initialized can result in load errors. ([#357][])
- Some scenarios where `middleware_names` could result in bad resource names ([#354][])
- ActionController instrumentation conflicting with some gems that monkey patch Rails ([#391][])

### Deprecated

- Use of `:datadog_rack_request_span` variable in favor of `'datadog.rack_request_span'` in Rack. ([#365][], [#392][])

### Refactored

- Racecar to use ActiveSupport::Notifications Subscriber module ([#381][])
- Rails to use ActiveRecord integration instead of its own implementation ([#396][])
- ActiveRecord to use ActiveSupport::Notifications Subscriber module ([#396][])

## [0.12.0.beta2] - 2018-02-28

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0.beta2

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.12.0.beta1...v0.12.0.beta2

### Fixed

- Loading the ddtrace library after Rails has fully initialized can result in load errors. ([#357][])

## [0.12.0.beta1] - 2018-02-09

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.12.0.beta1

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.2...v0.12.0.beta1

### Added

- GraphQL integration (supporting graphql 1.7.9+) ([#295][])
- ActiveRecord object instantiation tracing ([#311][], [#334][])
- `http.request_id` tag to Rack spans ([#335][])

## [0.11.4] - 2018-03-29

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.4

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.3...v0.11.4

### Fixed

- Transport body parsing when downgrading ([#369][])
- Transport incorrectly attempting to apply sampling to service metadata ([#370][])
- `sql.active_record` traces showing incorrect adapter settings when non-default adapter used ([#383][])

## [0.11.3] - 2018-03-06

Release notes: https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.3

Git diff: https://github.com/DataDog/dd-trace-rb/compare/v0.11.2...v0.11.3

### Added

- CHANGELOG.md ([#350][], [#363][]) ([@awendt][])
- `http.request_id` tag to Rack spans ([#335][])
- Tracer configuration to README.md ([#332][]) ([@noma4i][])

### Fixed

- Extra indentation in README.md ([#349][]) ([@ck3g][])
- `http.url` when Rails raises exceptions ([#351][], [#353][])
- Rails from being patched twice ([#352][])
- 4XX responses from middleware being marked as errors ([#345][])
- Rails exception middleware sometimes not being inserted at correct position ([#345][])
- Processing pipeline documentation typo ([#355][]) ([@MMartyn][])
- Loading the ddtrace library after Rails has fully initialized can result in load errors. ([#357][])
- Use of block syntax with Rails `render` not working ([#359][], [#360][]) ([@dorner][])

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

- `http.base_url` tag for Rack applications ([#301][], [#327][])
- `distributed_tracing` option to Sinatra ([#325][])
- `exception_controller` option to Rails ([#320][])

### Changed

- Decoupled Sinatra and ActiveRecord integrations ([#328][], [#330][]) ([@hawknewton][])
- Racecar uses preferred ActiveSupport::Notifications strategy ([#323][])

### Removed

- `Datadog::Monkey` in favor of newer configuration API ([#322][])

### Fixed

- Custom resource names from Rails controllers being overridden ([#321][])
- Custom Rails exception controllers reporting as the resource ([#320][])

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
[0.44.0]: https://github.com/DataDog/dd-trace-rb/compare/v0.43.0...v0.44.0
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

<!--- The following link definition list is generated by PimpMyChangelog --->
[#132]: https://github.com/DataDog/dd-trace-rb/issues/132
[#171]: https://github.com/DataDog/dd-trace-rb/issues/171
[#211]: https://github.com/DataDog/dd-trace-rb/issues/211
[#247]: https://github.com/DataDog/dd-trace-rb/issues/247
[#272]: https://github.com/DataDog/dd-trace-rb/issues/272
[#295]: https://github.com/DataDog/dd-trace-rb/issues/295
[#301]: https://github.com/DataDog/dd-trace-rb/issues/301
[#311]: https://github.com/DataDog/dd-trace-rb/issues/311
[#320]: https://github.com/DataDog/dd-trace-rb/issues/320
[#321]: https://github.com/DataDog/dd-trace-rb/issues/321
[#322]: https://github.com/DataDog/dd-trace-rb/issues/322
[#323]: https://github.com/DataDog/dd-trace-rb/issues/323
[#324]: https://github.com/DataDog/dd-trace-rb/issues/324
[#325]: https://github.com/DataDog/dd-trace-rb/issues/325
[#327]: https://github.com/DataDog/dd-trace-rb/issues/327
[#328]: https://github.com/DataDog/dd-trace-rb/issues/328
[#330]: https://github.com/DataDog/dd-trace-rb/issues/330
[#332]: https://github.com/DataDog/dd-trace-rb/issues/332
[#334]: https://github.com/DataDog/dd-trace-rb/issues/334
[#335]: https://github.com/DataDog/dd-trace-rb/issues/335
[#340]: https://github.com/DataDog/dd-trace-rb/issues/340
[#345]: https://github.com/DataDog/dd-trace-rb/issues/345
[#349]: https://github.com/DataDog/dd-trace-rb/issues/349
[#350]: https://github.com/DataDog/dd-trace-rb/issues/350
[#351]: https://github.com/DataDog/dd-trace-rb/issues/351
[#352]: https://github.com/DataDog/dd-trace-rb/issues/352
[#353]: https://github.com/DataDog/dd-trace-rb/issues/353
[#354]: https://github.com/DataDog/dd-trace-rb/issues/354
[#355]: https://github.com/DataDog/dd-trace-rb/issues/355
[#357]: https://github.com/DataDog/dd-trace-rb/issues/357
[#359]: https://github.com/DataDog/dd-trace-rb/issues/359
[#360]: https://github.com/DataDog/dd-trace-rb/issues/360
[#362]: https://github.com/DataDog/dd-trace-rb/issues/362
[#363]: https://github.com/DataDog/dd-trace-rb/issues/363
[#365]: https://github.com/DataDog/dd-trace-rb/issues/365
[#367]: https://github.com/DataDog/dd-trace-rb/issues/367
[#369]: https://github.com/DataDog/dd-trace-rb/issues/369
[#370]: https://github.com/DataDog/dd-trace-rb/issues/370
[#371]: https://github.com/DataDog/dd-trace-rb/issues/371
[#374]: https://github.com/DataDog/dd-trace-rb/issues/374
[#375]: https://github.com/DataDog/dd-trace-rb/issues/375
[#377]: https://github.com/DataDog/dd-trace-rb/issues/377
[#379]: https://github.com/DataDog/dd-trace-rb/issues/379
[#380]: https://github.com/DataDog/dd-trace-rb/issues/380
[#381]: https://github.com/DataDog/dd-trace-rb/issues/381
[#383]: https://github.com/DataDog/dd-trace-rb/issues/383
[#384]: https://github.com/DataDog/dd-trace-rb/issues/384
[#389]: https://github.com/DataDog/dd-trace-rb/issues/389
[#390]: https://github.com/DataDog/dd-trace-rb/issues/390
[#391]: https://github.com/DataDog/dd-trace-rb/issues/391
[#392]: https://github.com/DataDog/dd-trace-rb/issues/392
[#393]: https://github.com/DataDog/dd-trace-rb/issues/393
[#395]: https://github.com/DataDog/dd-trace-rb/issues/395
[#396]: https://github.com/DataDog/dd-trace-rb/issues/396
[#397]: https://github.com/DataDog/dd-trace-rb/issues/397
[#400]: https://github.com/DataDog/dd-trace-rb/issues/400
[#403]: https://github.com/DataDog/dd-trace-rb/issues/403
[#407]: https://github.com/DataDog/dd-trace-rb/issues/407
[#409]: https://github.com/DataDog/dd-trace-rb/issues/409
[#410]: https://github.com/DataDog/dd-trace-rb/issues/410
[#415]: https://github.com/DataDog/dd-trace-rb/issues/415
[#418]: https://github.com/DataDog/dd-trace-rb/issues/418
[#419]: https://github.com/DataDog/dd-trace-rb/issues/419
[#420]: https://github.com/DataDog/dd-trace-rb/issues/420
[#421]: https://github.com/DataDog/dd-trace-rb/issues/421
[#422]: https://github.com/DataDog/dd-trace-rb/issues/422
[#424]: https://github.com/DataDog/dd-trace-rb/issues/424
[#426]: https://github.com/DataDog/dd-trace-rb/issues/426
[#427]: https://github.com/DataDog/dd-trace-rb/issues/427
[#430]: https://github.com/DataDog/dd-trace-rb/issues/430
[#431]: https://github.com/DataDog/dd-trace-rb/issues/431
[#439]: https://github.com/DataDog/dd-trace-rb/issues/439
[#443]: https://github.com/DataDog/dd-trace-rb/issues/443
[#444]: https://github.com/DataDog/dd-trace-rb/issues/444
[#445]: https://github.com/DataDog/dd-trace-rb/issues/445
[#446]: https://github.com/DataDog/dd-trace-rb/issues/446
[#447]: https://github.com/DataDog/dd-trace-rb/issues/447
[#450]: https://github.com/DataDog/dd-trace-rb/issues/450
[#451]: https://github.com/DataDog/dd-trace-rb/issues/451
[#452]: https://github.com/DataDog/dd-trace-rb/issues/452
[#453]: https://github.com/DataDog/dd-trace-rb/issues/453
[#458]: https://github.com/DataDog/dd-trace-rb/issues/458
[#460]: https://github.com/DataDog/dd-trace-rb/issues/460
[#463]: https://github.com/DataDog/dd-trace-rb/issues/463
[#466]: https://github.com/DataDog/dd-trace-rb/issues/466
[#474]: https://github.com/DataDog/dd-trace-rb/issues/474
[#475]: https://github.com/DataDog/dd-trace-rb/issues/475
[#476]: https://github.com/DataDog/dd-trace-rb/issues/476
[#477]: https://github.com/DataDog/dd-trace-rb/issues/477
[#478]: https://github.com/DataDog/dd-trace-rb/issues/478
[#480]: https://github.com/DataDog/dd-trace-rb/issues/480
[#481]: https://github.com/DataDog/dd-trace-rb/issues/481
[#483]: https://github.com/DataDog/dd-trace-rb/issues/483
[#486]: https://github.com/DataDog/dd-trace-rb/issues/486
[#487]: https://github.com/DataDog/dd-trace-rb/issues/487
[#488]: https://github.com/DataDog/dd-trace-rb/issues/488
[#496]: https://github.com/DataDog/dd-trace-rb/issues/496
[#497]: https://github.com/DataDog/dd-trace-rb/issues/497
[#499]: https://github.com/DataDog/dd-trace-rb/issues/499
[#502]: https://github.com/DataDog/dd-trace-rb/issues/502
[#503]: https://github.com/DataDog/dd-trace-rb/issues/503
[#508]: https://github.com/DataDog/dd-trace-rb/issues/508
[#514]: https://github.com/DataDog/dd-trace-rb/issues/514
[#515]: https://github.com/DataDog/dd-trace-rb/issues/515
[#516]: https://github.com/DataDog/dd-trace-rb/issues/516
[#517]: https://github.com/DataDog/dd-trace-rb/issues/517
[#521]: https://github.com/DataDog/dd-trace-rb/issues/521
[#525]: https://github.com/DataDog/dd-trace-rb/issues/525
[#527]: https://github.com/DataDog/dd-trace-rb/issues/527
[#529]: https://github.com/DataDog/dd-trace-rb/issues/529
[#530]: https://github.com/DataDog/dd-trace-rb/issues/530
[#533]: https://github.com/DataDog/dd-trace-rb/issues/533
[#535]: https://github.com/DataDog/dd-trace-rb/issues/535
[#538]: https://github.com/DataDog/dd-trace-rb/issues/538
[#544]: https://github.com/DataDog/dd-trace-rb/issues/544
[#552]: https://github.com/DataDog/dd-trace-rb/issues/552
[#578]: https://github.com/DataDog/dd-trace-rb/issues/578
[#580]: https://github.com/DataDog/dd-trace-rb/issues/580
[#582]: https://github.com/DataDog/dd-trace-rb/issues/582
[#583]: https://github.com/DataDog/dd-trace-rb/issues/583
[#591]: https://github.com/DataDog/dd-trace-rb/issues/591
[#593]: https://github.com/DataDog/dd-trace-rb/issues/593
[#597]: https://github.com/DataDog/dd-trace-rb/issues/597
[#598]: https://github.com/DataDog/dd-trace-rb/issues/598
[#602]: https://github.com/DataDog/dd-trace-rb/issues/602
[#605]: https://github.com/DataDog/dd-trace-rb/issues/605
[#626]: https://github.com/DataDog/dd-trace-rb/issues/626
[#628]: https://github.com/DataDog/dd-trace-rb/issues/628
[#630]: https://github.com/DataDog/dd-trace-rb/issues/630
[#631]: https://github.com/DataDog/dd-trace-rb/issues/631
[#635]: https://github.com/DataDog/dd-trace-rb/issues/635
[#636]: https://github.com/DataDog/dd-trace-rb/issues/636
[#637]: https://github.com/DataDog/dd-trace-rb/issues/637
[#639]: https://github.com/DataDog/dd-trace-rb/issues/639
[#640]: https://github.com/DataDog/dd-trace-rb/issues/640
[#641]: https://github.com/DataDog/dd-trace-rb/issues/641
[#642]: https://github.com/DataDog/dd-trace-rb/issues/642
[#648]: https://github.com/DataDog/dd-trace-rb/issues/648
[#649]: https://github.com/DataDog/dd-trace-rb/issues/649
[#650]: https://github.com/DataDog/dd-trace-rb/issues/650
[#651]: https://github.com/DataDog/dd-trace-rb/issues/651
[#654]: https://github.com/DataDog/dd-trace-rb/issues/654
[#655]: https://github.com/DataDog/dd-trace-rb/issues/655
[#656]: https://github.com/DataDog/dd-trace-rb/issues/656
[#658]: https://github.com/DataDog/dd-trace-rb/issues/658
[#660]: https://github.com/DataDog/dd-trace-rb/issues/660
[#661]: https://github.com/DataDog/dd-trace-rb/issues/661
[#662]: https://github.com/DataDog/dd-trace-rb/issues/662
[#664]: https://github.com/DataDog/dd-trace-rb/issues/664
[#665]: https://github.com/DataDog/dd-trace-rb/issues/665
[#666]: https://github.com/DataDog/dd-trace-rb/issues/666
[#671]: https://github.com/DataDog/dd-trace-rb/issues/671
[#672]: https://github.com/DataDog/dd-trace-rb/issues/672
[#673]: https://github.com/DataDog/dd-trace-rb/issues/673
[#674]: https://github.com/DataDog/dd-trace-rb/issues/674
[#675]: https://github.com/DataDog/dd-trace-rb/issues/675
[#677]: https://github.com/DataDog/dd-trace-rb/issues/677
[#681]: https://github.com/DataDog/dd-trace-rb/issues/681
[#683]: https://github.com/DataDog/dd-trace-rb/issues/683
[#686]: https://github.com/DataDog/dd-trace-rb/issues/686
[#687]: https://github.com/DataDog/dd-trace-rb/issues/687
[#693]: https://github.com/DataDog/dd-trace-rb/issues/693
[#696]: https://github.com/DataDog/dd-trace-rb/issues/696
[#697]: https://github.com/DataDog/dd-trace-rb/issues/697
[#699]: https://github.com/DataDog/dd-trace-rb/issues/699
[#700]: https://github.com/DataDog/dd-trace-rb/issues/700
[#701]: https://github.com/DataDog/dd-trace-rb/issues/701
[#702]: https://github.com/DataDog/dd-trace-rb/issues/702
[#703]: https://github.com/DataDog/dd-trace-rb/issues/703
[#704]: https://github.com/DataDog/dd-trace-rb/issues/704
[#707]: https://github.com/DataDog/dd-trace-rb/issues/707
[#709]: https://github.com/DataDog/dd-trace-rb/issues/709
[#714]: https://github.com/DataDog/dd-trace-rb/issues/714
[#715]: https://github.com/DataDog/dd-trace-rb/issues/715
[#716]: https://github.com/DataDog/dd-trace-rb/issues/716
[#719]: https://github.com/DataDog/dd-trace-rb/issues/719
[#720]: https://github.com/DataDog/dd-trace-rb/issues/720
[#721]: https://github.com/DataDog/dd-trace-rb/issues/721
[#722]: https://github.com/DataDog/dd-trace-rb/issues/722
[#724]: https://github.com/DataDog/dd-trace-rb/issues/724
[#728]: https://github.com/DataDog/dd-trace-rb/issues/728
[#729]: https://github.com/DataDog/dd-trace-rb/issues/729
[#731]: https://github.com/DataDog/dd-trace-rb/issues/731
[#738]: https://github.com/DataDog/dd-trace-rb/issues/738
[#739]: https://github.com/DataDog/dd-trace-rb/issues/739
[#742]: https://github.com/DataDog/dd-trace-rb/issues/742
[#747]: https://github.com/DataDog/dd-trace-rb/issues/747
[#748]: https://github.com/DataDog/dd-trace-rb/issues/748
[#750]: https://github.com/DataDog/dd-trace-rb/issues/750
[#751]: https://github.com/DataDog/dd-trace-rb/issues/751
[#752]: https://github.com/DataDog/dd-trace-rb/issues/752
[#753]: https://github.com/DataDog/dd-trace-rb/issues/753
[#754]: https://github.com/DataDog/dd-trace-rb/issues/754
[#756]: https://github.com/DataDog/dd-trace-rb/issues/756
[#760]: https://github.com/DataDog/dd-trace-rb/issues/760
[#762]: https://github.com/DataDog/dd-trace-rb/issues/762
[#765]: https://github.com/DataDog/dd-trace-rb/issues/765
[#768]: https://github.com/DataDog/dd-trace-rb/issues/768
[#770]: https://github.com/DataDog/dd-trace-rb/issues/770
[#771]: https://github.com/DataDog/dd-trace-rb/issues/771
[#775]: https://github.com/DataDog/dd-trace-rb/issues/775
[#776]: https://github.com/DataDog/dd-trace-rb/issues/776
[#778]: https://github.com/DataDog/dd-trace-rb/issues/778
[#782]: https://github.com/DataDog/dd-trace-rb/issues/782
[#784]: https://github.com/DataDog/dd-trace-rb/issues/784
[#786]: https://github.com/DataDog/dd-trace-rb/issues/786
[#789]: https://github.com/DataDog/dd-trace-rb/issues/789
[#791]: https://github.com/DataDog/dd-trace-rb/issues/791
[#795]: https://github.com/DataDog/dd-trace-rb/issues/795
[#796]: https://github.com/DataDog/dd-trace-rb/issues/796
[#798]: https://github.com/DataDog/dd-trace-rb/issues/798
[#800]: https://github.com/DataDog/dd-trace-rb/issues/800
[#802]: https://github.com/DataDog/dd-trace-rb/issues/802
[#805]: https://github.com/DataDog/dd-trace-rb/issues/805
[#811]: https://github.com/DataDog/dd-trace-rb/issues/811
[#814]: https://github.com/DataDog/dd-trace-rb/issues/814
[#815]: https://github.com/DataDog/dd-trace-rb/issues/815
[#817]: https://github.com/DataDog/dd-trace-rb/issues/817
[#818]: https://github.com/DataDog/dd-trace-rb/issues/818
[#819]: https://github.com/DataDog/dd-trace-rb/issues/819
[#821]: https://github.com/DataDog/dd-trace-rb/issues/821
[#823]: https://github.com/DataDog/dd-trace-rb/issues/823
[#824]: https://github.com/DataDog/dd-trace-rb/issues/824
[#832]: https://github.com/DataDog/dd-trace-rb/issues/832
[#838]: https://github.com/DataDog/dd-trace-rb/issues/838
[#840]: https://github.com/DataDog/dd-trace-rb/issues/840
[#841]: https://github.com/DataDog/dd-trace-rb/issues/841
[#842]: https://github.com/DataDog/dd-trace-rb/issues/842
[#843]: https://github.com/DataDog/dd-trace-rb/issues/843
[#844]: https://github.com/DataDog/dd-trace-rb/issues/844
[#845]: https://github.com/DataDog/dd-trace-rb/issues/845
[#846]: https://github.com/DataDog/dd-trace-rb/issues/846
[#847]: https://github.com/DataDog/dd-trace-rb/issues/847
[#851]: https://github.com/DataDog/dd-trace-rb/issues/851
[#853]: https://github.com/DataDog/dd-trace-rb/issues/853
[#854]: https://github.com/DataDog/dd-trace-rb/issues/854
[#855]: https://github.com/DataDog/dd-trace-rb/issues/855
[#856]: https://github.com/DataDog/dd-trace-rb/issues/856
[#859]: https://github.com/DataDog/dd-trace-rb/issues/859
[#861]: https://github.com/DataDog/dd-trace-rb/issues/861
[#865]: https://github.com/DataDog/dd-trace-rb/issues/865
[#867]: https://github.com/DataDog/dd-trace-rb/issues/867
[#868]: https://github.com/DataDog/dd-trace-rb/issues/868
[#871]: https://github.com/DataDog/dd-trace-rb/issues/871
[#872]: https://github.com/DataDog/dd-trace-rb/issues/872
[#880]: https://github.com/DataDog/dd-trace-rb/issues/880
[#881]: https://github.com/DataDog/dd-trace-rb/issues/881
[#882]: https://github.com/DataDog/dd-trace-rb/issues/882
[#883]: https://github.com/DataDog/dd-trace-rb/issues/883
[#884]: https://github.com/DataDog/dd-trace-rb/issues/884
[#885]: https://github.com/DataDog/dd-trace-rb/issues/885
[#886]: https://github.com/DataDog/dd-trace-rb/issues/886
[#888]: https://github.com/DataDog/dd-trace-rb/issues/888
[#890]: https://github.com/DataDog/dd-trace-rb/issues/890
[#891]: https://github.com/DataDog/dd-trace-rb/issues/891
[#892]: https://github.com/DataDog/dd-trace-rb/issues/892
[#893]: https://github.com/DataDog/dd-trace-rb/issues/893
[#894]: https://github.com/DataDog/dd-trace-rb/issues/894
[#895]: https://github.com/DataDog/dd-trace-rb/issues/895
[#896]: https://github.com/DataDog/dd-trace-rb/issues/896
[#898]: https://github.com/DataDog/dd-trace-rb/issues/898
[#899]: https://github.com/DataDog/dd-trace-rb/issues/899
[#900]: https://github.com/DataDog/dd-trace-rb/issues/900
[#903]: https://github.com/DataDog/dd-trace-rb/issues/903
[#904]: https://github.com/DataDog/dd-trace-rb/issues/904
[#906]: https://github.com/DataDog/dd-trace-rb/issues/906
[#907]: https://github.com/DataDog/dd-trace-rb/issues/907
[#909]: https://github.com/DataDog/dd-trace-rb/issues/909
[#910]: https://github.com/DataDog/dd-trace-rb/issues/910
[#911]: https://github.com/DataDog/dd-trace-rb/issues/911
[#912]: https://github.com/DataDog/dd-trace-rb/issues/912
[#913]: https://github.com/DataDog/dd-trace-rb/issues/913
[#914]: https://github.com/DataDog/dd-trace-rb/issues/914
[#915]: https://github.com/DataDog/dd-trace-rb/issues/915
[#917]: https://github.com/DataDog/dd-trace-rb/issues/917
[#918]: https://github.com/DataDog/dd-trace-rb/issues/918
[#919]: https://github.com/DataDog/dd-trace-rb/issues/919
[#920]: https://github.com/DataDog/dd-trace-rb/issues/920
[#921]: https://github.com/DataDog/dd-trace-rb/issues/921
[#927]: https://github.com/DataDog/dd-trace-rb/issues/927
[#928]: https://github.com/DataDog/dd-trace-rb/issues/928
[#929]: https://github.com/DataDog/dd-trace-rb/issues/929
[#930]: https://github.com/DataDog/dd-trace-rb/issues/930
[#932]: https://github.com/DataDog/dd-trace-rb/issues/932
[#933]: https://github.com/DataDog/dd-trace-rb/issues/933
[#934]: https://github.com/DataDog/dd-trace-rb/issues/934
[#935]: https://github.com/DataDog/dd-trace-rb/issues/935
[#937]: https://github.com/DataDog/dd-trace-rb/issues/937
[#938]: https://github.com/DataDog/dd-trace-rb/issues/938
[#940]: https://github.com/DataDog/dd-trace-rb/issues/940
[#942]: https://github.com/DataDog/dd-trace-rb/issues/942
[#943]: https://github.com/DataDog/dd-trace-rb/issues/943
[#944]: https://github.com/DataDog/dd-trace-rb/issues/944
[#945]: https://github.com/DataDog/dd-trace-rb/issues/945
[#947]: https://github.com/DataDog/dd-trace-rb/issues/947
[#948]: https://github.com/DataDog/dd-trace-rb/issues/948
[#949]: https://github.com/DataDog/dd-trace-rb/issues/949
[#950]: https://github.com/DataDog/dd-trace-rb/issues/950
[#951]: https://github.com/DataDog/dd-trace-rb/issues/951
[#952]: https://github.com/DataDog/dd-trace-rb/issues/952
[#953]: https://github.com/DataDog/dd-trace-rb/issues/953
[#954]: https://github.com/DataDog/dd-trace-rb/issues/954
[#955]: https://github.com/DataDog/dd-trace-rb/issues/955
[#956]: https://github.com/DataDog/dd-trace-rb/issues/956
[#957]: https://github.com/DataDog/dd-trace-rb/issues/957
[#960]: https://github.com/DataDog/dd-trace-rb/issues/960
[#961]: https://github.com/DataDog/dd-trace-rb/issues/961
[#964]: https://github.com/DataDog/dd-trace-rb/issues/964
[#965]: https://github.com/DataDog/dd-trace-rb/issues/965
[#966]: https://github.com/DataDog/dd-trace-rb/issues/966
[#967]: https://github.com/DataDog/dd-trace-rb/issues/967
[#968]: https://github.com/DataDog/dd-trace-rb/issues/968
[#969]: https://github.com/DataDog/dd-trace-rb/issues/969
[#971]: https://github.com/DataDog/dd-trace-rb/issues/971
[#972]: https://github.com/DataDog/dd-trace-rb/issues/972
[#973]: https://github.com/DataDog/dd-trace-rb/issues/973
[#974]: https://github.com/DataDog/dd-trace-rb/issues/974
[#975]: https://github.com/DataDog/dd-trace-rb/issues/975
[#977]: https://github.com/DataDog/dd-trace-rb/issues/977
[#980]: https://github.com/DataDog/dd-trace-rb/issues/980
[#981]: https://github.com/DataDog/dd-trace-rb/issues/981
[#982]: https://github.com/DataDog/dd-trace-rb/issues/982
[#983]: https://github.com/DataDog/dd-trace-rb/issues/983
[#985]: https://github.com/DataDog/dd-trace-rb/issues/985
[#986]: https://github.com/DataDog/dd-trace-rb/issues/986
[#988]: https://github.com/DataDog/dd-trace-rb/issues/988
[#989]: https://github.com/DataDog/dd-trace-rb/issues/989
[#990]: https://github.com/DataDog/dd-trace-rb/issues/990
[#991]: https://github.com/DataDog/dd-trace-rb/issues/991
[#993]: https://github.com/DataDog/dd-trace-rb/issues/993
[#995]: https://github.com/DataDog/dd-trace-rb/issues/995
[#996]: https://github.com/DataDog/dd-trace-rb/issues/996
[#997]: https://github.com/DataDog/dd-trace-rb/issues/997
[#1000]: https://github.com/DataDog/dd-trace-rb/issues/1000
[#1004]: https://github.com/DataDog/dd-trace-rb/issues/1004
[#1005]: https://github.com/DataDog/dd-trace-rb/issues/1005
[#1006]: https://github.com/DataDog/dd-trace-rb/issues/1006
[#1008]: https://github.com/DataDog/dd-trace-rb/issues/1008
[#1009]: https://github.com/DataDog/dd-trace-rb/issues/1009
[#1010]: https://github.com/DataDog/dd-trace-rb/issues/1010
[#1015]: https://github.com/DataDog/dd-trace-rb/issues/1015
[#1021]: https://github.com/DataDog/dd-trace-rb/issues/1021
[#1023]: https://github.com/DataDog/dd-trace-rb/issues/1023
[#1027]: https://github.com/DataDog/dd-trace-rb/issues/1027
[#1030]: https://github.com/DataDog/dd-trace-rb/issues/1030
[#1031]: https://github.com/DataDog/dd-trace-rb/issues/1031
[#1032]: https://github.com/DataDog/dd-trace-rb/issues/1032
[#1033]: https://github.com/DataDog/dd-trace-rb/issues/1033
[#1034]: https://github.com/DataDog/dd-trace-rb/issues/1034
[#1035]: https://github.com/DataDog/dd-trace-rb/issues/1035
[#1037]: https://github.com/DataDog/dd-trace-rb/issues/1037
[#1041]: https://github.com/DataDog/dd-trace-rb/issues/1041
[#1043]: https://github.com/DataDog/dd-trace-rb/issues/1043
[#1045]: https://github.com/DataDog/dd-trace-rb/issues/1045
[#1046]: https://github.com/DataDog/dd-trace-rb/issues/1046
[#1047]: https://github.com/DataDog/dd-trace-rb/issues/1047
[#1051]: https://github.com/DataDog/dd-trace-rb/issues/1051
[#1054]: https://github.com/DataDog/dd-trace-rb/issues/1054
[#1057]: https://github.com/DataDog/dd-trace-rb/issues/1057
[#1062]: https://github.com/DataDog/dd-trace-rb/issues/1062
[#1070]: https://github.com/DataDog/dd-trace-rb/issues/1070
[#1071]: https://github.com/DataDog/dd-trace-rb/issues/1071
[#1072]: https://github.com/DataDog/dd-trace-rb/issues/1072
[#1073]: https://github.com/DataDog/dd-trace-rb/issues/1073
[#1074]: https://github.com/DataDog/dd-trace-rb/issues/1074
[#1075]: https://github.com/DataDog/dd-trace-rb/issues/1075
[#1076]: https://github.com/DataDog/dd-trace-rb/issues/1076
[#1079]: https://github.com/DataDog/dd-trace-rb/issues/1079
[#1081]: https://github.com/DataDog/dd-trace-rb/issues/1081
[#1082]: https://github.com/DataDog/dd-trace-rb/issues/1082
[#1086]: https://github.com/DataDog/dd-trace-rb/issues/1086
[#1089]: https://github.com/DataDog/dd-trace-rb/issues/1089
[#1090]: https://github.com/DataDog/dd-trace-rb/issues/1090
[#1091]: https://github.com/DataDog/dd-trace-rb/issues/1091
[#1092]: https://github.com/DataDog/dd-trace-rb/issues/1092
[#1099]: https://github.com/DataDog/dd-trace-rb/issues/1099
[#1100]: https://github.com/DataDog/dd-trace-rb/issues/1100
[#1103]: https://github.com/DataDog/dd-trace-rb/issues/1103
[#1104]: https://github.com/DataDog/dd-trace-rb/issues/1104
[#1105]: https://github.com/DataDog/dd-trace-rb/issues/1105
[#1107]: https://github.com/DataDog/dd-trace-rb/issues/1107
[#1109]: https://github.com/DataDog/dd-trace-rb/issues/1109
[#1115]: https://github.com/DataDog/dd-trace-rb/issues/1115
[#1116]: https://github.com/DataDog/dd-trace-rb/issues/1116
[#1118]: https://github.com/DataDog/dd-trace-rb/issues/1118
[#1119]: https://github.com/DataDog/dd-trace-rb/issues/1119
[#1120]: https://github.com/DataDog/dd-trace-rb/issues/1120
[#1121]: https://github.com/DataDog/dd-trace-rb/issues/1121
[#1122]: https://github.com/DataDog/dd-trace-rb/issues/1122
[#1124]: https://github.com/DataDog/dd-trace-rb/issues/1124
[#1125]: https://github.com/DataDog/dd-trace-rb/issues/1125
[#1126]: https://github.com/DataDog/dd-trace-rb/issues/1126
[#1127]: https://github.com/DataDog/dd-trace-rb/issues/1127
[#1128]: https://github.com/DataDog/dd-trace-rb/issues/1128
[#1129]: https://github.com/DataDog/dd-trace-rb/issues/1129
[#1131]: https://github.com/DataDog/dd-trace-rb/issues/1131
[#1133]: https://github.com/DataDog/dd-trace-rb/issues/1133
[#1134]: https://github.com/DataDog/dd-trace-rb/issues/1134
[#1137]: https://github.com/DataDog/dd-trace-rb/issues/1137
[#1138]: https://github.com/DataDog/dd-trace-rb/issues/1138
[#1141]: https://github.com/DataDog/dd-trace-rb/issues/1141
[#1145]: https://github.com/DataDog/dd-trace-rb/issues/1145
[#1146]: https://github.com/DataDog/dd-trace-rb/issues/1146
[#1148]: https://github.com/DataDog/dd-trace-rb/issues/1148
[#1149]: https://github.com/DataDog/dd-trace-rb/issues/1149
[#1150]: https://github.com/DataDog/dd-trace-rb/issues/1150
[#1151]: https://github.com/DataDog/dd-trace-rb/issues/1151
[#1152]: https://github.com/DataDog/dd-trace-rb/issues/1152
[#1153]: https://github.com/DataDog/dd-trace-rb/issues/1153
[#1154]: https://github.com/DataDog/dd-trace-rb/issues/1154
[#1155]: https://github.com/DataDog/dd-trace-rb/issues/1155
[#1156]: https://github.com/DataDog/dd-trace-rb/issues/1156
[#1157]: https://github.com/DataDog/dd-trace-rb/issues/1157
[#1158]: https://github.com/DataDog/dd-trace-rb/issues/1158
[#1159]: https://github.com/DataDog/dd-trace-rb/issues/1159
[#1160]: https://github.com/DataDog/dd-trace-rb/issues/1160
[#1162]: https://github.com/DataDog/dd-trace-rb/issues/1162
[#1163]: https://github.com/DataDog/dd-trace-rb/issues/1163
[#1165]: https://github.com/DataDog/dd-trace-rb/issues/1165
[#1172]: https://github.com/DataDog/dd-trace-rb/issues/1172
[#1173]: https://github.com/DataDog/dd-trace-rb/issues/1173
[#1176]: https://github.com/DataDog/dd-trace-rb/issues/1176
[#1177]: https://github.com/DataDog/dd-trace-rb/issues/1177
[#1178]: https://github.com/DataDog/dd-trace-rb/issues/1178
[#1179]: https://github.com/DataDog/dd-trace-rb/issues/1179
[#1180]: https://github.com/DataDog/dd-trace-rb/issues/1180
[#1181]: https://github.com/DataDog/dd-trace-rb/issues/1181
[#1182]: https://github.com/DataDog/dd-trace-rb/issues/1182
[#1183]: https://github.com/DataDog/dd-trace-rb/issues/1183
[#1184]: https://github.com/DataDog/dd-trace-rb/issues/1184
[#1185]: https://github.com/DataDog/dd-trace-rb/issues/1185
[#1186]: https://github.com/DataDog/dd-trace-rb/issues/1186
[#1187]: https://github.com/DataDog/dd-trace-rb/issues/1187
[#1188]: https://github.com/DataDog/dd-trace-rb/issues/1188
[#1189]: https://github.com/DataDog/dd-trace-rb/issues/1189
[#1195]: https://github.com/DataDog/dd-trace-rb/issues/1195
[#1198]: https://github.com/DataDog/dd-trace-rb/issues/1198
[#1199]: https://github.com/DataDog/dd-trace-rb/issues/1199
[#1200]: https://github.com/DataDog/dd-trace-rb/issues/1200
[#1203]: https://github.com/DataDog/dd-trace-rb/issues/1203
[#1204]: https://github.com/DataDog/dd-trace-rb/issues/1204
[#1210]: https://github.com/DataDog/dd-trace-rb/issues/1210
[#1212]: https://github.com/DataDog/dd-trace-rb/issues/1212
[#1213]: https://github.com/DataDog/dd-trace-rb/issues/1213
[#1216]: https://github.com/DataDog/dd-trace-rb/issues/1216
[#1217]: https://github.com/DataDog/dd-trace-rb/issues/1217
[#1218]: https://github.com/DataDog/dd-trace-rb/issues/1218
[#1220]: https://github.com/DataDog/dd-trace-rb/issues/1220
[#1225]: https://github.com/DataDog/dd-trace-rb/issues/1225
[#1226]: https://github.com/DataDog/dd-trace-rb/issues/1226
[#1227]: https://github.com/DataDog/dd-trace-rb/issues/1227
[#1229]: https://github.com/DataDog/dd-trace-rb/issues/1229
[#1232]: https://github.com/DataDog/dd-trace-rb/issues/1232
[#1233]: https://github.com/DataDog/dd-trace-rb/issues/1233
[#1234]: https://github.com/DataDog/dd-trace-rb/issues/1234
[#1235]: https://github.com/DataDog/dd-trace-rb/issues/1235
[#1236]: https://github.com/DataDog/dd-trace-rb/issues/1236
[#1237]: https://github.com/DataDog/dd-trace-rb/issues/1237
[#1238]: https://github.com/DataDog/dd-trace-rb/issues/1238
[#1239]: https://github.com/DataDog/dd-trace-rb/issues/1239
[#1243]: https://github.com/DataDog/dd-trace-rb/issues/1243
[#1244]: https://github.com/DataDog/dd-trace-rb/issues/1244
[#1248]: https://github.com/DataDog/dd-trace-rb/issues/1248
[#1256]: https://github.com/DataDog/dd-trace-rb/issues/1256
[#1257]: https://github.com/DataDog/dd-trace-rb/issues/1257
[#1262]: https://github.com/DataDog/dd-trace-rb/issues/1262
[#1263]: https://github.com/DataDog/dd-trace-rb/issues/1263
[#1264]: https://github.com/DataDog/dd-trace-rb/issues/1264
[#1266]: https://github.com/DataDog/dd-trace-rb/issues/1266
[#1267]: https://github.com/DataDog/dd-trace-rb/issues/1267
[#1268]: https://github.com/DataDog/dd-trace-rb/issues/1268
[#1269]: https://github.com/DataDog/dd-trace-rb/issues/1269
[#1270]: https://github.com/DataDog/dd-trace-rb/issues/1270
[#1272]: https://github.com/DataDog/dd-trace-rb/issues/1272
[#1273]: https://github.com/DataDog/dd-trace-rb/issues/1273
[#1275]: https://github.com/DataDog/dd-trace-rb/issues/1275
[#1276]: https://github.com/DataDog/dd-trace-rb/issues/1276
[#1277]: https://github.com/DataDog/dd-trace-rb/issues/1277
[#1278]: https://github.com/DataDog/dd-trace-rb/issues/1278
[#1279]: https://github.com/DataDog/dd-trace-rb/issues/1279
[#1281]: https://github.com/DataDog/dd-trace-rb/issues/1281
[#1283]: https://github.com/DataDog/dd-trace-rb/issues/1283
[#1284]: https://github.com/DataDog/dd-trace-rb/issues/1284
[#1286]: https://github.com/DataDog/dd-trace-rb/issues/1286
[#1287]: https://github.com/DataDog/dd-trace-rb/issues/1287
[#1289]: https://github.com/DataDog/dd-trace-rb/issues/1289
[#1293]: https://github.com/DataDog/dd-trace-rb/issues/1293
[#1295]: https://github.com/DataDog/dd-trace-rb/issues/1295
[#1296]: https://github.com/DataDog/dd-trace-rb/issues/1296
[#1297]: https://github.com/DataDog/dd-trace-rb/issues/1297
[#1298]: https://github.com/DataDog/dd-trace-rb/issues/1298
[#1299]: https://github.com/DataDog/dd-trace-rb/issues/1299
[@Azure7111]: https://github.com/Azure7111
[@BabyGroot]: https://github.com/BabyGroot
[@DocX]: https://github.com/DocX
[@EpiFouloux]: https://github.com/EpiFouloux
[@JamesHarker]: https://github.com/JamesHarker
[@Jared-Prime]: https://github.com/Jared-Prime
[@Joas1988]: https://github.com/Joas1988
[@JustSnow]: https://github.com/JustSnow
[@MMartyn]: https://github.com/MMartyn
[@NobodysNightmare]: https://github.com/NobodysNightmare
[@Redapted]: https://github.com/Redapted
[@Sticksword]: https://github.com/Sticksword
[@Supy]: https://github.com/Supy
[@Yurokle]: https://github.com/Yurokle
[@ZimbiX]: https://github.com/ZimbiX
[@agirlnamedsophia]: https://github.com/agirlnamedsophia
[@ahammel]: https://github.com/ahammel
[@al-kudryavtsev]: https://github.com/al-kudryavtsev
[@alksl]: https://github.com/alksl
[@alloy]: https://github.com/alloy
[@aurelian]: https://github.com/aurelian
[@awendt]: https://github.com/awendt
[@bartekbsh]: https://github.com/bartekbsh
[@benhutton]: https://github.com/benhutton
[@bheemreddy181]: https://github.com/bheemreddy181
[@blaines]: https://github.com/blaines
[@brafales]: https://github.com/brafales
[@bzf]: https://github.com/bzf
[@callumj]: https://github.com/callumj
[@cjford]: https://github.com/cjford
[@ck3g]: https://github.com/ck3g
[@cswatt]: https://github.com/cswatt
[@dasch]: https://github.com/dasch
[@dim]: https://github.com/dim
[@dirk]: https://github.com/dirk
[@djmb]: https://github.com/djmb
[@dorner]: https://github.com/dorner
[@drcapulet]: https://github.com/drcapulet
[@elyalvarado]: https://github.com/elyalvarado
[@ericmustin]: https://github.com/ericmustin
[@erict-square]: https://github.com/erict-square
[@errriclee]: https://github.com/errriclee
[@evan-waters]: https://github.com/evan-waters
[@fledman]: https://github.com/fledman
[@frsantos]: https://github.com/frsantos
[@gaborszakacs]: https://github.com/gaborszakacs
[@giancarlocosta]: https://github.com/giancarlocosta
[@gingerlime]: https://github.com/gingerlime
[@gottfrois]: https://github.com/gottfrois
[@guizmaii]: https://github.com/guizmaii
[@hawknewton]: https://github.com/hawknewton
[@hs-bguven]: https://github.com/hs-bguven
[@illdelph]: https://github.com/illdelph
[@jamiehodge]: https://github.com/jamiehodge
[@janz93]: https://github.com/janz93
[@jeffjo]: https://github.com/jeffjo
[@jfrancoist]: https://github.com/jfrancoist
[@joeyAghion]: https://github.com/joeyAghion
[@jpaulgs]: https://github.com/jpaulgs
[@jvalanen]: https://github.com/jvalanen
[@kelvin-acosta]: https://github.com/kelvin-acosta
[@kissrobber]: https://github.com/kissrobber
[@kitop]: https://github.com/kitop
[@letiesperon]: https://github.com/letiesperon
[@link04]: https://github.com/link04
[@mantrala]: https://github.com/mantrala
[@matchbookmac]: https://github.com/matchbookmac
[@mberlanda]: https://github.com/mberlanda
[@mdehoog]: https://github.com/mdehoog
[@mdross95]: https://github.com/mdross95
[@michaelkl]: https://github.com/michaelkl
[@mstruve]: https://github.com/mstruve
[@mustela]: https://github.com/mustela
[@nic-lan]: https://github.com/nic-lan
[@noma4i]: https://github.com/noma4i
[@norbertnytko]: https://github.com/norbertnytko
[@palin]: https://github.com/palin
[@pj0tr]: https://github.com/pj0tr
[@psycholein]: https://github.com/psycholein
[@pzaich]: https://github.com/pzaich
[@rahul342]: https://github.com/rahul342
[@randy-girard]: https://github.com/randy-girard
[@renchap]: https://github.com/renchap
[@ricbartm]: https://github.com/ricbartm
[@roccoblues]: https://github.com/roccoblues
[@sco11morgan]: https://github.com/sco11morgan
[@senny]: https://github.com/senny
[@shayonj]: https://github.com/shayonj
[@sinsoku]: https://github.com/sinsoku
[@soulcutter]: https://github.com/soulcutter
[@stefanahman]: https://github.com/stefanahman
[@steveh]: https://github.com/steveh
[@stormsilver]: https://github.com/stormsilver
[@sullimander]: https://github.com/sullimander
[@tjgrathwell]: https://github.com/tjgrathwell
[@tjwp]: https://github.com/tjwp
[@tomasv]: https://github.com/tomasv
[@tonypinder]: https://github.com/tonypinder
[@twe4ked]: https://github.com/twe4ked
[@undergroundwebdesigns]: https://github.com/undergroundwebdesigns
[@vramaiah]: https://github.com/vramaiah
[@walterking]: https://github.com/walterking
[@y-yagi]: https://github.com/y-yagi
[@zachmccormick]: https://github.com/zachmccormick