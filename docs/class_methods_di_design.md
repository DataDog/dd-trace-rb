# Class Methods in Symbol Database

## What Are Class Methods in Ruby?

In Ruby, class methods are defined on the singleton class of the class object:

```ruby
class User
  def digest(string)       # instance method — User#digest
    BCrypt::Password.create(string)
  end

  def self.digest(string)  # class method — User.digest
    BCrypt::Password.create(string)
  end
end
```

Both can coexist with the same name. They are completely separate methods accessed
through different lookup chains.

## Cross-Language Equivalents

| Language | Equivalent | Same name as instance method possible? | DI support |
|----------|-----------|---------------------------------------|-----------|
| Ruby | `def self.foo` (singleton method) | Yes | No (see below) |
| Java | `static` method | Yes — resolves via `INVOKEVIRTUAL` vs `INVOKESTATIC` | Yes |
| C# (.NET) | `static` method | Yes | Yes |
| JavaScript | `static foo()` | Yes | Yes |
| Python | `@classmethod` / `@staticmethod` | No — second definition overwrites first | Yes |
| Go | Package-level function | Not applicable (no classes) | Yes (functions) |

Java, C#, and JavaScript all support same-name instance + class methods and DI
instruments both. Python avoids the naming collision entirely.

## Why Ruby Class Methods Are Not Uploaded by Default

Ruby DI instruments methods by prepending a module to a class's instance method
lookup chain:

```ruby
cls.prepend(instrumentation_module)
```

This intercepts calls to **instance methods** (`cls.instance_method(:foo)`).
It does **not** affect the singleton class. To instrument a class method, DI
would need:

```ruby
cls.singleton_class.prepend(instrumentation_module)
```

This is not currently implemented in `lib/datadog/di/instrumenter.rb` — it only
calls `cls.instance_method(method_name).source_location` (line 104) and never
touches the singleton class.

**Consequence:** Including class method scopes in symdb payloads would present
completions in the DI UI for methods that cannot be probed. This is misleading
and potentially confusing for users.

## Backend Disambiguation: Java Static vs Instance Methods

For languages where the same method name can exist as both instance and static,
the probe specification uses the `signature` field in `Where` (Java's probe location):

```java
// com.datadog.debugger.probe.Where
String typeName;    // "com.example.User"
String methodName;  // "digest"
String signature;   // "(Ljava/lang/String;)Ljava/lang/String;" — JVM descriptor
```

The JVM method descriptor encodes parameter and return types. Since static and
instance methods both appear in the class's method table but with different
descriptors (static methods don't have an implicit `this`), the signature
disambiguates them.

For Ruby, `method_type: "class"` in `language_specifics` serves this purpose once
DI supports class method instrumentation.

## Current Implementation

Class methods are extracted but **gated behind an internal setting**:

```ruby
# Default: false — class methods not uploaded
Datadog.configuration.symbol_database.internal.upload_class_methods

# Or via env var (internal use only):
DD_INTERNAL_SYMBOL_DATABASE_UPLOAD_CLASS_METHODS=true
```

When enabled, class methods are emitted as `METHOD` scopes with:
- `name: "method_name"` (bare name, no `self.` prefix)
- `language_specifics.method_type: "class"`

The bare name (no `self.` prefix) matches Java/C# conventions. The
`method_type: "class"` field disambiguates from instance methods with the
same name — this is the standard cross-language approach used by all other
Datadog tracers.

## Path to Enabling Class Methods

1. Implement singleton class instrumentation in `lib/datadog/di/instrumenter.rb`:
   - Detect `method_type: "class"` in probe definition
   - Use `cls.singleton_class.prepend(...)` instead of `cls.prepend(...)`
   - Use `cls.singleton_class.instance_method(name)` for source location lookup

2. Switch default to `true` and move setting from `internal` to public:
   ```ruby
   option :upload_class_methods do |o|
     o.type :bool
     o.default true  # once DI instruments class methods
   end
   ```

3. The backend already stores `method_type` and can use it for DI UI completions
   once the tracer can deliver on the probe.

## Probe Spec Disambiguation (UI → Tracer via RC)

The probe specification sent from the backend to the tracer via Remote Config uses
`MethodProbeLocation` (TypeScript type in web-ui):

```typescript
// packages/api/endpoints/live-debugger/types/probe/probe-location.types.ts
type MethodProbeLocation = {
    typeName: string;    // e.g. "User"
    methodName: string;  // e.g. "digest"
    signature?: string;  // e.g. "String(Number, Object)" — optional
};
```

There is **no `isClassMethod` or `isStatic` boolean** in the probe spec. For Java,
disambiguation relies on the `signature` field: since static and instance methods have
different JVM descriptors (static omits the implicit `this` parameter), the tracer can
match the signature to the bytecode `MethodNode.access & Opcodes.ACC_STATIC`.

**For Ruby, this approach doesn't work** because Ruby methods are untyped — a class
method `def self.digest(string)` and instance method `def digest(string)` have
identical `Method#parameters` output: `[[:req, :string]]`. There is no signature
to distinguish them.

**When Ruby DI adds class method support**, either:
1. A new boolean field must be added to `MethodProbeLocation` (e.g. `isClassMethod`)
2. Or the `signature` field is repurposed with a Ruby-specific convention

This requires coordination between the web-ui, backend probe spec, and Ruby tracer.

## `self` as an Implicit Argument

Ruby DI emits `self` as the first `ARG` symbol for **instance methods** only.
`self` is not in `Method#parameters` (it's implicit), but it must be registered so
DI expression language can evaluate `self.name`, `self.class`, etc. at a probe point.

For **class methods**, `self` is the class object itself — still accessible but less
useful for DI expression evaluation, and not emitted to keep parity with other tracers.

```ruby
# In extract_method_parameters (extractor.rb):
self_arg = if method_type == :instance
  [Symbol.new(symbol_type: 'ARG', name: 'self', line: UNKNOWN_MIN_LINE)]
else
  []  # class methods: self not emitted
end
```

## UI: How the Frontend Surfaces Methods

The frontend uses these symdb API endpoints (web-ui/packages/api/endpoints/live-debugger/):
- `/api/unstable/symdb-api/scopes/search` — search by class/method name
- `/api/unstable/symdb-api/completions/scope/method` — get completions for a method probe

The `DebuggerSymbolApi` type returned from search does NOT include `method_type` — the
`LanguageSpecifics` type exposed to the frontend has `accessModifiers`, `annotations`,
`interfaces`, `superClasses`, `returnType`, but no `method_type` or `isStatic`.

**Implication:** Even if we upload class methods, the UI currently cannot distinguish
them from instance methods in the search results. The `method_type: "class"` field
is stored in the backend database but not surfaced to the frontend. Surfacing it would
require a frontend change to `LanguageSpecifics` and UI rendering logic.

## References

- `lib/datadog/di/instrumenter.rb:104` — current instance-method-only lookup
- `lib/datadog/symbol_database/extractor.rb` — `extract_singleton_method_scope`, `extract_method_parameters`
- `lib/datadog/symbol_database/configuration/settings.rb` — `upload_class_methods` setting
- `debugger-backend/debugger-common/.../TracerVersionChecker.kt` — language min versions
- `web-ui/packages/api/endpoints/live-debugger/types/probe/probe-location.types.ts` — probe spec
- `web-ui/packages/api/endpoints/live-debugger/types/symdb-scopes.types.ts` — LanguageSpecifics type
