# Dynamic Instrumentation

## Overview

Dynamic Instrumentation for Ruby is in **limited preview**.
While the core functionality is stable, some features available in other
languages (Java, Python, .NET) are not available for Ruby.

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
  - Only MRI (CRuby) is supported; JRuby and other Ruby implementations are not supported
  - The `libdatadog_api` C extension must be compiled; DI will not
    activate without it
- Rack-based applications only
  - Includes Rails, Sinatra, and other Rack-compatible frameworks
  - Non-Rack applications are not supported
  - Background processes and jobs (including Sidekiq, Resque, etc.) are not supported
- [Remote Configuration Management](https://docs.datadoghq.com/remote_configuration/) enabled
  - Remote Configuration is enabled by default.
  - If it's disabled, follow the [instructions to enable it](https://docs.datadoghq.com/remote_configuration/#enable-remote-configuration).
- **Development environments are not supported**

## Getting Started

There are two ways to turn on Dynamic Instrumentation: from your service
configuration (the env-var path) or from the Datadog UI when you create a
probe (the in-app / "implicit" enablement path). Either is sufficient.

### Option A: Enable from service configuration

1. Enable Dynamic Instrumentation:

       export DD_DYNAMIC_INSTRUMENTATION_ENABLED=true

2. Ensure you are using a production environment (`RAILS_ENV=production`,
   etc.).
3. Ensure you have DD_ENV set:

       export DD_ENV=prod

4. Ensure you set the source code metadata tags:

       export DD_GIT_REPOSITORY_URL=https://github.com/example-org/repo
       export DD_GIT_COMMIT_SHA=`git rev-parse HEAD`

### Option B: Enable from the Datadog UI ("implicit enablement")

If `DD_DYNAMIC_INSTRUMENTATION_ENABLED` is unset, the tracer will still
listen for an enablement signal from remote configuration. Creating a
probe in the Datadog UI sends that signal, and the tracer turns on
Dynamic Instrumentation without an application restart.

The DD_ENV and source code metadata variables (steps 3 and 4 above)
still need to be set for probes to appear correctly in the UI.

**Precedence:** if `DD_DYNAMIC_INSTRUMENTATION_ENABLED=false` is set
explicitly, the env-var setting takes precedence and remote-config
enablement is ignored. Leave the variable unset (do not set it to
`false`) to allow UI-driven enablement.

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

Ruby Dynamic Instrumentation supports **log probes**, which can be
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
- Local variables defined within the method are not captured
- **Workaround:** Use line probes inside the method if you need to
  capture local variables at specific points during execution
- Method probes can only target instance methods. Class/singleton methods
  (defined via `def self.method_name`, `class << self`, or `module_function`)
  cannot be instrumented with method probes. Line probes inside class
  methods still work since line probes are not method-bound.

**Additional considerations:**
- Stack traces are always captured, but methods defined via
  `method_missing` or similar metaprogramming will be omitted from the
  call chain because they don't have a source location in Ruby's
  internal representation

**Use method probes when:**
- You want to understand method inputs and outputs
- You're debugging method-level behavior
- You need to track method execution time

### Not Supported

The following probe types available in other languages are not
supported for Ruby:

- Metric probes
- Span probes
- Dynamic span tags

## Capture Expressions

Log probes can carry a list of *capture expressions*: named DSL
expressions whose evaluated values are emitted in the snapshot under
the `captureExpressions` block. Capture expressions are an alternative
to `captureSnapshot: true` — they let you pick exactly which values to
capture instead of the whole local/argument scope.

Each capture expression carries:

- `name` — the key used in the snapshot output. Must match
  `^[a-zA-Z0-9_?]+$`.
- `expr` — a DSL expression evaluated against the probe scope (uses
  the same expression language as `when` conditions and message
  templates).
- `capture` (optional) — per-expression
  `maxReferenceDepth` / `maxCollectionSize` / `maxLength` /
  `maxFieldCount` override.

Behavior notes for Ruby:

- **Snapshot vs. capture expressions are mutually exclusive at fire
  time.** If a probe sets both `captureSnapshot: true` and a non-empty
  `captureExpressions`, the full snapshot is emitted and the
  capture-expression values are dropped. This matches the
  Python/Java/Go behavior and supports graceful degradation for older
  tracer versions that lack capture-expression support.
- **Per-field fallback.** Limits absent from a per-expression
  `capture` block fall back to the probe-level `capture` and then to
  the tracer's default settings, independently per field.
- **Rate-limit default.** A probe with `captureExpressions` set
  defaults to the snapshot bucket of 1 invocation/second, not the
  log-message bucket. Override with `sampling.snapshotsPerSecond` on
  the probe.
- **Per-fire time budget.** Capture-expression evaluation for one
  probe fire is bounded by `DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS`
  (default `200`). When exceeded, remaining expressions are emitted
  with `"notCapturedReason": "timeout"` so the truncation is visible
  in the snapshot UI.
- **Evaluation errors are visible.** When an individual expression
  fails to evaluate, its key is omitted from `captureExpressions`
  and an `{ expr: <name>, message: … }` entry is added to the
  snapshot's `evaluationErrors` array.

Known limitation: per-expression `maxLength` and `maxCollectionSize`
overrides are not yet honored end-to-end; the tracer falls back to the
DI settings defaults for these two fields. Per-expression
`maxReferenceDepth` and `maxFieldCount` work as documented.

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

**Important:** Dynamic instrumentation cannot report when line
probes target non-executable lines. Setting line probes on non-executable
lines will succeed (the UI will report that the code is instrumented, if
the referenced file is loaded and tracked), but no snapshots will be
generated.

## Code Loading and Instrumentation

### Application Must Be Processing Requests
- Dynamic Instrumentation is initialized via Rack middleware when
  processing HTTP requests
- An application that has just booted but has not served any requests
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
  is not finalized for customer use
- **Workaround:** Increase the capture depth for probes targeting code
  that works with complex objects

#### Custom Serializers

Custom serializers allow you to define how specific objects are serialized
in Dynamic Instrumentation snapshots. The API is internal and
subject to change.

**Exception Handling:** If a custom serializer's condition lambda raises
an exception (for example, a regex match against a string with invalid
UTF-8 encoding), the exception will be logged at WARN level, then the
serializer will be skipped and the next serializer will be tried. This
prevents custom serializers from breaking the entire serialization process.
The value will fall back to default serialization.

## What Data Is Captured

Dynamic instrumentation sends some of the application data to Datadog.

**Probe snapshots** (captured when probes fire):

- **Variable values** — local variables, method arguments, and return
  values, subject to the capture depth and collection size limits
  described below. Values are automatically redacted when their
  identifier names match built-in redaction rules. You can also
  configure additional identifiers and class names to redact.
- **Object class names** — the class of each captured value.
- **Exception details** (method probes only) — the exception class name
  and the message passed to the exception's constructor.
  - The reported message is the value given to the constructor, not the
    return value of the `message` method. If a custom exception class
    overrides `message`, the reported value may differ.
  - If the constructor argument is not a string (or is nil), the
    exception type is still reported but the message will show as
    redacted.
- **Stack traces** — the call stack at the point the probe fires.

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

Symbol Database upload is disabled by default. To enable it, set:

    export DD_SYMBOL_DATABASE_UPLOAD_ENABLED=true

Once enabled, the upload activates via Remote Configuration when you open
the DI UI for your service.

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
