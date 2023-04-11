# Datadog Trace Client

[![Gem](https://img.shields.io/gem/v/ddtrace)](https://rubygems.org/gems/ddtrace/)
[![CircleCI](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master.svg?style=svg&circle-token=b0bd5ef866ec7f7b018f48731bb495f2d1372cc1)](https://circleci.com/gh/DataDog/dd-trace-rb/tree/master)
[![codecov](https://codecov.io/gh/DataDog/dd-trace-rb/branch/master/graph/badge.svg)](https://app.codecov.io/gh/DataDog/dd-trace-rb/branch/master)
[![YARD documentation](https://img.shields.io/badge/YARD-documentation-blue)][api docs]

``ddtrace`` is Datadog’s tracing client for Ruby. It is used to trace requests as they flow across web servers,
databases and microservices so that developers have great visiblity into bottlenecks and troublesome requests.

## Getting started

**If you're upgrading from a 0.x version, check out our [upgrade guide](https://github.com/DataDog/dd-trace-rb/blob/master/docs/UpgradeGuide.md#from-0x-to-10).**

For a basic product overview, check out our [setup documentation][setup docs].

For installation, configuration, and details about using the API, check out our [API documentation][api docs] and [gem documentation][gem docs].

For descriptions of terminology used in APM, take a look at the [official documentation][visualization docs].

For contributing, checkout the [contribution guidelines][contribution docs] and [development guide][development docs].

[setup docs]: https://docs.datadoghq.com/tracing/setup/ruby/
[api docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/GettingStarted.md
[gem docs]: https://datadog.github.io/dd-trace-rb/
[visualization docs]: https://docs.datadoghq.com/tracing/visualization/
[contribution docs]: https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md
[development docs]: https://github.com/DataDog/dd-trace-rb/blob/master/docs/DevelopmentGuide.md

## Special thanks

* [Mike Fiedler](https://github.com/miketheman) for working on a number of Datadog Ruby projects, as well as graciously
  gifting control of the `datadog` gem
