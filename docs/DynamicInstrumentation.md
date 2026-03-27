# Dynamic Instrumentation

## Overview

Dynamic Instrumentation for Ruby is currently in **limited preview**.
While the core functionality is stable, some features available in other
languages (Java, Python, .NET) are not yet available for Ruby.

> **New to Dynamic Instrumentation?**
> This document covers Ruby-specific setup and limitations. For an
> introduction to Dynamic Instrumentation concepts, probe types, and UI
> workflow, see:
> - [Dynamic Instrumentation overview](https://docs.datadoghq.com/dynamic_instrumentation/)
> - [Expression Language reference](https://docs.datadoghq.com/dynamic_instrumentation/expression-language/)

This document covers Ruby-specific considerations, limitations, and best
practices for using Dynamic Instrumentation.

## Platform Requirements

- Datadog Agent 7.49.0 or higher
- Ruby 2.6 or higher
  - Only MRI (CRuby) is supported; JRuby and other Ruby implementations are not currently supported
- Rack-based applications only
  - Includes Rails, Sinatra, and other Rack-compatible frameworks
  - Non-Rack applications are not currently supported
  - Background processes and jobs (including Sidekiq, Resque, etc.) are not yet supported
- [Remote Configuration Management](https://docs.datadoghq.com/remote_configuration/) enabled
  - Remote Configuration is enabled by default.
  - If it's disabled, follow the [instructions to enable it](https://docs.datadoghq.com/remote_configuration/#enable-remote-configuration).
- **Development environments are not supported**

## Getting Started

To use dynamic instrumentation:

1. Enable Dynamic Instrumentation:

       export DD_DYNAMIC_INSTRUMENTATION_ENABLED=true

2. Ensure you are using a production environment (`RAILS_ENV=production`,
   etc.).
3. Ensure you have DD_ENV set:

       export DD_ENV=prod

4. Ensure you set the source code metadata tags:

       export DD_GIT_REPOSITORY_URL=https://github.com/example-org/repo
       export DD_GIT_COMMIT_SHA=`git rev-parse HEAD`

## Creating Your First Probe

After setting the environment variables and restarting your application:

1. Navigate to [APM > Dynamic Instrumentation](https://app.datadoghq.com/dynamic-instrumentation) in the Datadog UI
2. Select your service and environment
3. Browse to the file and line you want to instrument
4. Create a log probe to capture variable values

For detailed instructions on creating and configuring probes, see the
[Dynamic Instrumentation documentation](https://docs.datadoghq.com/dynamic_instrumentation/).

## Probe Types

### Currently Supported

Ruby Dynamic Instrumentation currently supports **log probes**, which can be
created as either line probes or method probes.

#### Line Probes

Line probes capture data at a specific line of code. They can be installed
on lines containing executable code and the final lines of a method (which
returns the method's value).

**What line probes capture:**
- Local variables at that point in execution
- Method parameters (when the probe is inside a method)
- Stack traces
- Execution context

**Use line probes when:**
- You need to inspect state at a specific point in a method
- You want to capture local variables mid-execution
- You're debugging a specific calculation or branch

#### Method Probes

Method probes instrument method entry and exit points, capturing data about
the entire method execution.

**What method probes capture:**
- Method arguments at entry
- Return value at exit
- Method execution duration
- Exceptions raised

**Limitations:**
- Local variables defined within the method are not currently captured
- **Workaround:** Use line probes inside the method if you need to
  capture local variables at specific points during execution

**Additional considerations:**
- Stack traces are always captured, but methods defined via
  `method_missing` or similar metaprogramming will be omitted from the
  call chain because they don't have a source location in Ruby's
  internal representation

**Use method probes when:**
- You want to understand method inputs and outputs
- You're debugging method-level behavior
- You need to track method execution time

### Not Yet Supported

The following probe types available in other languages are not yet
supported for Ruby:

- Metric probes
- Span probes
- Dynamic span tags

## Expression Language

The Ruby tracer supports Dynamic Instrumentation expression language for
setting conditions on probes and for message templates in log messages.

### Instance Variable Name Conflicts

Ruby differs from other programming languages supported by Dynamic
Instrumentation in that instance variables are prefixed with the `@`
sign. This creates a conflict because expression language uses `@` to
refer to the following special variables:

- `@return` - The return value of the method
- `@duration` - The duration of the method execution
- `@exception` - Any exception raised by the method
- `@it` - Current item in collection operations
- `@key` - Current key in hash operations
- `@value` - Current value in hash operations

**Important:** If you have instance variables with the above names, they
will NOT be accessible via expression language expressions since the
special DI variables will override them. You must rename the variables in
your program if you use any of these variables and wish to refer to them
from expression language expressions.

### Field Access

- `getmember` looks up instance variables directly, not attributes (which
  look like method calls, and could be implemented via methods)
- This means computed properties or attributes defined via methods won't
  be accessible
- DI avoids running application code as much as possible for safety and
  performance reasons

### Ruby-Specific Behavior

- Accessing nonexistent array indices and nonexistent hash keys via
  indexing yields `nil` (which is the Ruby language behavior) rather than
  an error, as in some other languages' implementations of expression
  language
- Since expression language evaluation is done in Ruby, it is not
  possible to guarantee that it will not invoke application code (since
  all operations in Ruby can be redefined at runtime, even for example
  addition of numbers)

### Type Support in Expression Language Operations

Some expression language operations have limited type support:
- `len()` - Only supports Array, String, Hash
- `isEmpty()` - Only supports nil, Numeric, Array, String
- `contains()` - Only supports String in String or Array operations

Using these operations on unsupported types will raise an error and
prevent the probe condition from being evaluated.

## Instrumentable Code

Line probes can be installed on lines containing executable code and the
final lines of a method (which returns the method's value). The
following example Ruby method is annotated with which lines can be
targeted by dynamic instrumentation:

    def foo(param)              # No    (*1)
      rv = if param == 1        # Yes
        'yes'                   # Yes
      else                      # No
        'no'                    # Yes
      end                       # No    (*2)
      rv                        # Yes
    end                         # Yes   (*3)

### Lines That Cannot Be Instrumented

When setting line probes, the following lines **cannot** be targeted:
- Method definition lines (the `def` line itself - *1)
- `else` and `elsif` clauses
- `end` keywords (except the final `end` of a method - *3)
- Comment-only lines
- Empty lines

**Note:** The method definition line (*1) is technically executable and
can be targeted if you wish to instrument the method definition itself,
but if you want to instrument the defined method's execution, you must
set the line probe on a line inside of the method.

**Important:** Dynamic instrumentation cannot currently report when line
probes target non-executable lines. Setting line probes on non-executable
lines will succeed (the UI will report that the code is instrumented, if
the referenced file is loaded and tracked), but no snapshots will be
generated.

## Code Loading and Instrumentation

### Code Tracking Requirement
- Files must be loaded **after** Dynamic Instrumentation code tracking
  starts
- Code loaded before the tracer initializes cannot be instrumented with
  line probes
- Method probes can still work for classes defined before code tracking
  starts
- Best practice: Ensure the Datadog tracer initializes early in your
  application boot process

### Application Must Be Processing Requests
- Dynamic Instrumentation is initialized via Rack middleware when
  processing HTTP requests
- An application that has just booted but has not yet served any requests
  will not have Dynamic Instrumentation activated
- Dynamic Instrumentation will be automatically activated when the first
  HTTP request is processed

### File Path Matching
- When creating a line probe, if multiple files match the path you
  specify, instrumentation will fail
- You'll need to provide a more specific file path to target the correct
  file
- Use unique file paths when creating line probes to avoid ambiguity

### Eval'd Code
- Code executed via `eval()` cannot be targeted by Dynamic
  Instrumentation
- Only code in physical files (required or loaded) can be instrumented

## Data Capture Limits

### Snapshot Size

- Maximum snapshot size is **1 MB**
- Snapshots exceeding this size will be dropped entirely
- Consider reducing capture depth or collection sizes if you encounter
  this limit

### Default Capture Limits

The following limits control how much data is captured in each snapshot:

- **Depth**: 3 levels of nested objects/collections
- **Collection size**: 100 elements for arrays and hashes
- **String length**: 255 characters
- **Attributes per object**: 20 instance variables

These limits can be configured globally via environment variables or
per-probe in the probe definition.

### Complex Objects

- ActiveRecord models and similar complex objects may not capture useful
  data at the default depth of 3
- Their attributes are often nested deeper than 3 levels
- Custom serializers are available for internal Datadog use but the API
  is not yet finalized for customer use
- **Workaround:** Increase the capture depth for probes targeting code
  that works with complex objects

#### Custom Serializers

Custom serializers allow you to define how specific objects are serialized
in Dynamic Instrumentation snapshots. The API is currently internal and
subject to change.

**Exception Handling:** If a custom serializer's condition lambda raises
an exception (for example, a regex match against a string with invalid
UTF-8 encoding), the exception will be logged at WARN level, then the
serializer will be skipped and the next serializer will be tried. This
prevents custom serializers from breaking the entire serialization process.
The value will fall back to default serialization.

## Application Data Sent to Datadog

Dynamic instrumentation sends some of the application data to Datadog.

**Probe snapshots** (captured when probes fire):

- Class names of objects
- Serialized object values, subject to redaction. There are built-in
  redaction rules based on identifier names that are always active.
  Additionally, it is possible to provide a list of class names whose
  object values should always be redacted, and a list of additional
  identifiers to be redacted.
- Exception class names and messages
- Exception stack traces

**Symbol Database** (uploaded once at startup, see below):

- Class, module, and method names from user application code
- Method parameter names (not values)
- Source file paths and line ranges
- File content hashes (for source code version matching)
- No runtime values, variable contents, or application data

## Symbol Database

The Symbol Database powers auto-completion in the Dynamic Instrumentation
UI. When enabled, the tracer extracts symbol information (classes,
modules, methods, parameters) from your running application and uploads
it to Datadog via the Agent. This allows the DI UI to suggest class
names, method names, and method parameters when creating probes.

### Enabling the Symbol Database

Symbol Database upload is enabled by default when Dynamic Instrumentation
is enabled. No additional configuration is required. It activates via
Remote Configuration when the DI UI is opened for your service.

To explicitly disable it:

    export DD_SYMBOL_DATABASE_UPLOAD_ENABLED=false

For testing without Remote Configuration:

    export DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD=true

### What Is Extracted

The Symbol Database extracts metadata about your application's structure.
It does **not** extract runtime values, variable contents, or any data
that flows through your application.

**Extracted:**
- Class and module names
- Method names and parameter names (not values)
- Method visibility (public, private, protected)
- Class inheritance (`superclass`) and module inclusion
  (`included_modules`, `prepended_modules`)
- Class variables and constants (names only, not values)
- Source file paths and line ranges
- File content hashes (Git-compatible SHA-1, for commit inference)

**Note on generated methods:** Methods generated by `attr_writer`,
`attr_accessor`, ActiveRecord associations, and similar metaprogramming
are **not extracted**. Their `source_location` points to gem or stdlib
code (e.g. `activerecord/lib/...`, `forwardable.rb`), so they are
filtered out along with other non-user code. Only methods whose source
is in your application files appear in autocomplete.

**Not extracted:**
- Instance variable names or values
- Local variable names or values
- Method return types (Ruby is dynamically typed)
- Runtime data of any kind

### What Is Uploaded

Symbol data is uploaded to the Datadog Agent as compressed JSON via the
`/symdb/v1/input` endpoint. The Agent forwards it to the Datadog
backend. Uploads occur once at startup (after Remote Configuration
enables the feature) and are deduplicated — the same symbols are not
re-uploaded unless the application restarts.

### Which Code Is Included

Only **user application code** is extracted. The following are
automatically excluded:

- All installed gems (detected via `/gems/` in the source path)
- Ruby standard library
- The Datadog tracer itself (`Datadog::` namespace)
- Test code (`/spec/`, `/test/` paths)
- Code loaded via `eval()`

This means internal or private gems installed via Bundler are also
excluded. There is currently no mechanism to force-include specific
gems.

### Behavior Differences from Other Tracers

Ruby's Symbol Database implementation differs from Java, Python, and
.NET in several ways:

#### Scope hierarchy

Ruby uses `FILE` as the root scope type (one per source file), with
`CLASS` or `MODULE` scopes nested inside. Java uses `JAR`, .NET uses
`ASSEMBLY`, and Python uses `MODULE` (one per Python module file).
Within each root scope, all tracers extract `CLASS` and `METHOD` scopes.

#### Code filtering

Java, Python, and .NET ship curated lists of known third-party package
names (600+ to 5,000 entries) and support `DD_THIRD_PARTY_DETECTION_EXCLUDES`
to force-include specific libraries. Ruby uses path-based filtering
(`/gems/`, `/ruby/`) instead, which is effective for Ruby's gem
ecosystem but does not support overrides. The
`DD_THIRD_PARTY_DETECTION_INCLUDES` and `DD_THIRD_PARTY_DETECTION_EXCLUDES`
environment variables are not yet implemented for Ruby.

#### Deferred features

The following features available in other tracers are not yet
implemented for Ruby:

- **Instance variable extraction** (FIELD symbols) — Java and .NET
  extract class fields; Ruby would require runtime introspection or
  source parsing
- **Local variable extraction** (LOCAL scopes) — Java and .NET extract
  local variables from bytecode/PDB debug info; not available via Ruby
  introspection
- **Closure/block scopes** — .NET extracts lambda and async closure
  scopes; Ruby blocks, procs, and lambdas are not yet extracted
- **Payload splitting** — Java splits uploads exceeding 50 MB into
  smaller chunks; Ruby skips the upload entirely if it exceeds 50 MB
  (unlikely for typical applications)
- **Fork deduplication** — Python coordinates uploads across forked
  workers (Gunicorn, uWSGI); Ruby does not yet deduplicate uploads in
  preforking servers (Puma clustered mode, Unicorn, Passenger), meaning
  each worker uploads independently
- **Injectable line information** — Go and .NET report which lines
  within a method can accept probes; Ruby does not include this metadata

#### Class methods

Class methods (`def self.foo`) are extracted but **not uploaded** by
default. Ruby's Dynamic Instrumentation can only instrument instance
methods (via `prepend`), so including class methods would present
completions for methods that cannot be probed. This may change when DI
gains singleton class instrumentation support.

## Rate Limiting and Performance

### Default Rate Limits

To minimize performance impact, probes have default rate limits:

- **Non-capturing probes**: 5,000 invocations per second
- **Capturing probes** (with snapshots): 1 invocation per second

These limits can be configured per probe in the probe definition.

### Circuit Breaker

Dynamic Instrumentation includes an automatic circuit breaker to protect
application performance:

- If a probe's execution overhead exceeds **0.5 seconds of CPU time**, it
  will be automatically disabled
- This prevents probes from significantly impacting application
  performance
- The probe will need to be recreated in the UI if you want to re-enable
  it
- This threshold can be configured globally

## Getting Help

For the latest updates, known issues, and to provide feedback, please
contact Datadog support or your account team.
