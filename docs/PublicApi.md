# Public API

`ddtrace` respects [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

Classes, modules, and methods marked as part of the public API will not introduce
breaking changes outside of a major version release.

Objects that belong to the public API are marked with the `@public_api` YARD documentation tag.
When navigating [`ddtrace`'s YARD documentation](https://rubydoc.info/gems/ddtrace), public API
objects will have an explicit banner informing the user that they are part of the public API contract.

Objects not marked with the `@public_api` tag are not part of the public API contract, and thus
considered internal to `ddtrace`. These objects can receive breaking changes in minor and patch
releases.
