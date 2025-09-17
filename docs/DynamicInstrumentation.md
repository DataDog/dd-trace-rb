# Dynamic Instrumentation

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
