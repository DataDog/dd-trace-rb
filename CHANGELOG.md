# Changelog

## [Unreleased (stable)]

## [Unreleased (beta)]

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

[Unreleased (stable)]: https://github.com/DataDog/dd-trace-rb/compare/v0.17.1...master
[Unreleased (beta)]: https://github.com/DataDog/dd-trace-rb/compare/v0.17.1...0.18-dev
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
