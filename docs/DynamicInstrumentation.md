# Dynamic Instrumentation

## Overview

Dynamic Instrumentation for Ruby is currently in **limited preview**.
While the core functionality is stable, some features available in other
languages (Java, Python, .NET) are not yet available for Ruby.

This document covers Ruby-specific considerations, limitations, and best
practices for using Dynamic Instrumentation.

## Getting Started

To use dynamic instrumentation:

1. Ensure you are using a production environment (RAILS_ENV=production,
   etc.).
2. Ensure you have DD_ENV set:

       export DD_ENV=prod

3. Ensure you set the source code metadata tags:

       export DD_GIT_REPOSITORY_URL=https://github.com/example-org/repo
       export DD_GIT_COMMIT_SHA=`git rev-parse HEAD`

## Platform Requirements

### Supported Ruby Versions
- Requires Ruby 2.6 or higher
- Only MRI (CRuby) is supported; JRuby and other Ruby implementations
  are not currently supported

### Environment Restrictions
- **Development environments are not supported**

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

## Expression Language

The Ruby tracer supports Dynamic Instrumentation expression language for
setting conditions on probes. Message templates are coming soon.

### Instance Variable Name Conflicts

Ruby differs from other programming languages supported by Dynamic
Instrumentation in that instance variables are prefixed with the `@`
sign. This creates a conflict because expression language uses `@` to
refer to the following special variables:

- `@return` - The return value of the method
- `@duration` - The duration of the method execution
- `@exception` - Any exception thrown by the method
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

## Method Probes

Method probes instrument method entry and exit points.

### Local Variable Capture

- Method probes capture arguments at method entry and the return value at
  exit
- Local variables defined within the method are not currently captured
- **Workaround:** Use line probes inside the method if you need to
  capture local variables at specific points during execution

### Dynamic Methods

- Methods defined via `method_missing` or similar metaprogramming may not
  appear correctly in stack traces
- The probe will still execute, but location information may be
  incomplete

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

## Application Data Sent to Datadog

Dynamic instrumentation sends some of the application data to Datadog.
The following data is generally sent:

- Class names of objects
- Serialized object values, subject to redaction. There are built-in
  redaction rules based on identifier names that are always active.
  Additionally, it is possible to provide a list of class names whose
  object values should always be redacted, and a list of additional
  identifiers to be redacted.
- Exception class names and messages
- Exception stack traces

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

## Probe Types

### Currently Supported

- **Log probes** - Capture snapshots with variable values, stack traces,
  and context

### Not Yet Supported

The following probe types available in other languages are not yet
supported for Ruby:

- Metric probes
- Span probes
- Dynamic span tags

## Getting Help

For the latest updates, known issues, and to provide feedback, please
contact Datadog support or your account team.
