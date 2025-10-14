# Dynamic Instrumentation

## Instrumentable Code

Instrumentation can be installed on lines containing executable code and
the final lines of a method (which does not contain executable code).
The following example Ruby method is annotated with which lines can be
targeted by dynamic instrumentation:

    def foo(param)              # No    (*1)
      rv = if param == 1        # Yes
        'yes'                   # Yes
      else                      # No
        'no'                    # Yes
      end                       # No    (*2)
      rv                        # Yes
    end                         # Yes   (*3)

Note that the method definition line (*1) is executable and can be targeted
if you wish to instrument the method definition, but if you want to instrument
the defined method, you must set the line probe on a line inside of the
method and not on the method definition line itself.

Note that only the "end" that ends a method definition is specially handled
(*3); other "end" lines, such as (*2), are not instrumentable.

Dynamic instrumentation is not currently able to report when line probes target
non-executable lines. Setting line probes on non-executable lines will succeed
(the UI will report that the code is instrumented, if the referenced file
is loaded and tracked), but no events will be emitted.

## Expression Language

`dd-trace-rb` supports Dynamic Instrumentation expression language for
setting conditions on probes (support for message templates is coming soon).

Ruby differs from other programming languages supported by Dynamic
Instrumentation in that instance variables are prefixed with the `@` sign.
This creates a conflict because expression language uses `@` to refer to
the following special variables:

- `@return`
- `@duration`
- `@exception`
- `@it`
- `@key`
- `@value`

If you have instance variables with the above names, they will NOT be
accessible via expression language expressions since the special DI
variables will override them. You must rename the variables in your program
if you use any of these variables and wish to refer to them from
expression language expressions.

Additionally, please note the following aspects of the expression language
implementation in `dd-trace-rb`:

- Accessing nonexistent array indices and nonexistent hash keys via
indexing yields `nil` (which is the Ruby language behavior)
rather than an error, as in some other languages' implementations of
expression language.
- `getmember` looks up instance variables, not attributes (which look
like method calls, and could be implemented via methods).
DI avoids running application code as much as possible for safety and
performance reasons.
- Since expression language evaluation is done in Ruby, it is not
possible to guarantee that it will not invoke application code
(since all operations in Ruby can be redefined at runtime, even for example
addition of numbers).

## Application Data Sent to Datadog

Dynamic instrumentation sends some of the application data to Datadog.
The following data is generally sent:

- Class names of objects.
- Serialized object values, subject to redaction. There are built-in
redaction rules based on identifier names that are always active.
Additionally, it is possible to provide a list of class names whose
object values should always be redacted, and a list of additional
identifiers to be redacted.
- Exception class names and messages.
- Exception stack traces.
