# Upstream Improvements

Typing gaps that could be resolved by contributing to upstream RBS definitions
(either `ruby/rbs` for stdlib or gem-specific RBS repos).

## String#unpack1 — overload for format-specific return types

**File:** `ruby/rbs` stdlib — `core/string.rbs`

**Problem:** `String#unpack1` currently has a single broad return type:
`(String fmt) -> (Integer | Float | String | nil)`. This is correct in general,
but for well-known format strings the return type is always narrower. For
example, the `'m0'` (base64 strict) format always returns a `String`.

**Suggested improvement:** Add overloads for specific format strings:

```rbs
def unpack1: ('m0') -> String
           | ('m') -> String
           | (String fmt) -> (Integer | Float | String | nil)
```

**Why it matters for us:** `Datadog::Core::Utils::Base64#strict_decode64` uses
`str.unpack1('m0')` and currently requires an inline `#: String` assertion
because Steep cannot verify the return type statically. With this upstream
change, the assertion would be unnecessary.

**References:**
- Our workaround: `lib/datadog/core/utils/base64.rb`
- RBS repo: https://github.com/ruby/rbs
