# Contributing

Community contributions to the Datadog tracing library for Ruby are welcome! See below for some basic guidelines.

## Want to request a new feature?

Many great ideas for new features come from the community, and we'd be happy to consider yours!

To share your request, you can [open a Github issue](https://github.com/DataDog/dd-trace-rb/issues/new) with the details about what you'd like to see. At a minimum, please provide:

 - The goal of the new feature
 - A description of how it might be used or behave
 - Links to any important resources (e.g. Github repos, websites, screenshots, specifications, diagrams)

Additionally, if you can, include:

 - A description of how it could be accomplished
 - Code snippets that might demonstrate its use or implementation
 - Screenshots or mockups that visually demonstrate the feature
 - Links to similar features that would serve as a good comparison
 - (Any other details that would be useful for implementing this feature!)

## Found a bug?

For any urgent matters (such as outages) or issues concerning the Datadog service or UI, contact our support team via https://docs.datadoghq.com/help/ for direct, faster assistance.

You may submit bug reports concerning the Datadog tracing library for Ruby by [opening a Github issue](https://github.com/DataDog/dd-trace-rb/issues/new). At a minimum, please provide:

 - A description of the problem
 - Steps to reproduce
 - Expected behavior
 - Actual behavior
 - Errors (with stack traces) or warnings received
 - Any details you can share about your configuration including:
    - Ruby version & platform
    - `datadog` version
    - Versions of any other relevant gems (or a `Gemfile.lock` if available)
    - Any configuration settings for the trace library (e.g. `initializers/datadog.rb`)

If at all possible, also provide:

 - Logs (from the tracer/application/agent) or other diagnostics
 - Screenshots, links, or other visual aids that are publicly accessible
 - Code sample or test that reproduces the problem
 - An explanation of what causes the bug and/or how it can be fixed

Reports that include rich detail are better, and ones with code that reproduce the bug are best.

## Have a patch?

We welcome code contributions to the library, which you can [submit as a pull request](https://github.com/DataDog/dd-trace-rb/pull/new/master). To create a pull request:

1. **Fork the repository** from https://github.com/DataDog/dd-trace-rb
2. **Make any changes** for your patch.
3. **Write tests** that demonstrate how the feature works or how the bug is fixed. See the [DevelopmentGuide](https://github.com/DataDog/dd-trace-rb/blob/master/docs/DevelopmentGuide.md) for detailed test instructions.
4. **Update any documentation** such as `docs/GettingStarted.md`, especially for new features.
5. **Submit the pull request** from your fork back to the latest revision of the `master` branch on https://github.com/DataDog/dd-trace-rb.

The pull request will be run through our CI pipeline, and a project member will review the changes with you. At a minimum, to be accepted and merged, pull requests must:

 - Have a stated goal and detailed description of the changes made
 - Include thorough test coverage and documentation, where applicable
 - Pass all tests and code quality checks (linting/coverage/benchmarks) on CI
 - Receive at least one approval from a project member with push permissions

We also recommend that you share in your description:

 - Any motivations or intent for the contribution
 - Links to any issues/pull requests it might be related to
 - Links to any webpages or other external resources that might be related to the change
 - Screenshots, code samples, or other visual aids that demonstrate the changes or how they are implemented
 - Benchmarks if the feature is anticipated to have performance implications
 - Any limitations, constraints or risks that are important to consider

For more information on common topics such as debugging locally, or how to write new integrations, check out [our development guide](https://github.com/DataDog/dd-trace-rb/blob/master/docs/DevelopmentGuide.md). If at any point you have a question or need assistance with your pull request, feel free to mention a project member! We're always happy to help contributors with their pull requests.

If your pull request fails a check that doesn't seem to be related to your change,
retry the check a few times to see if it resolves. If it doesn't, open an issue on the repo.

## Final word

Many thanks to all of our contributors, and looking forward to seeing you on Github! :tada:

 - Datadog Ruby APM Team
