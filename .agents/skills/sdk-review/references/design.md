# Design

Where code belongs, who owns state, and API and type shape.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line and no `Not when:` applies, or when it has a clear problem in this lens's area that no rule covers (mark it `no rule`). Cite the rule ID and propose the concrete alternative.

## 1. Ownership and boundaries

### DES-1.1: Route product operations through the product's module facade, not new methods on `Components`
- Flag: product-specific methods or readers added to `Core::Configuration::Components`, or product code calling `Datadog.send(:components)` directly.
- ❌ `Datadog.send(:components).activate_open_feature!(self)`
- ✅ `Datadog::OpenFeature.activate_provider(self)` (like the existing `Datadog::OpenFeature.engine`)

### DES-1.2: Don't add product fields to `ComponentsState`
- Flag: a product-specific field on `ComponentsState` that carries state across component rebuilds; that state belongs to the product's facade or object.

### DES-1.3: Give each shared registry one owner and one responsibility
- Flag: an object created by one component but mutated by another, or a registry mixing wire-format bits, subscriptions, and dispatch routing (for example, `Remote::Client::Capabilities`).

### DES-1.4: Split distinct concerns into their own objects
- Flag: a class gaining flat private methods for a second concern (for example, `TraceContext` building tracestate vendor entries beside traceparent parsing). Propose moving every method of the second concern into one new object, not only some of them.

### DES-1.5: Keep scripts and rake tasks single-purpose
- Flag: a new check added to an existing task or script whose original purpose is different, even when the two are related (for example, orphaned-lockfile detection added to the orphaned-gemfile script or to the dependency audit task). Propose a separate task; do not endorse extending the existing one.

## 2. API and type shape

### DES-2.1: Return one decision value, not a tuple whose parts determine each other
- Flag: a method returning `[bool, reason]` (worse on a `?` predicate, where an array is always truthy), or a store returning `[value, created?]`.
- ❌ `def emit_with_reason?(probe) = [false, :rate_limited]`
- ✅ `def admission(probe) = :rate_limited` (and let the caller own create-or-return logic for stores)

### DES-2.2: Inject an object instead of a boolean flag
- Flag: a constructor gaining a boolean that switches behaviour (`otel_thread_context: true`) where an object could hold that behaviour and its event subscriptions.

### DES-2.3: Make injected collaborators optional with a null-object default
- Flag: a new required keyword collaborator that the gem always supplies and every test must stub.

### DES-2.4: Group values that always travel together into a value object
- Flag: two or more values produced together and passed as a pair through several classes (for example, `otel_random_value` and `otel_threshold`).
- Not when: separate keyword arguments are a deliberate boundary that keeps an external SDK's types out of internal code.

### DES-2.5: Put conditions about an object's state in a named predicate on that object
- Flag: compound checks of another object's attributes inline at the call site. (`respond_to?` chains silenced with `steep:ignore` are `CONV-2.1`.)
- ❌ `if probe.capture_snapshot? && probe.type == :method && !probe.capture_expressions.empty?`
- ✅ `if probe.capture_entry_expressions?`

## 3. Settings and public surface

### DES-3.1: Name a settings namespace after its env var prefix, and don't repeat the prefix in option names
- Flag: `DD_FOO_*` options under a namespace other than `c.foo`, or option names such as `c.foo.foo_enabled`.
- ❌ `c.open_feature.feature_flags_enabled # DD_FEATURE_FLAGS_ENABLED`
- ✅ `c.feature_flags.enabled`, with scoped options nested as `c.feature_flags.agentless.base_url`

### DES-3.2: Treat span names, resources, and tags as a customer contract
- Flag: a change to how a span's `resource`, name, or service is computed with no description of the customer impact (monitors, dashboards, and facets keyed on the old value).

### DES-3.3: Pin external data sets by commit and fetch them lazily instead of vendoring them
- Flag: a large set of fixtures or data copied from another repo. Pin a SHA in a version file and fetch into `tmp/` from a rake task, as for the system-tests ref and `.gitlab/one-pipeline.locked.yml`.

## Don't flag
- Proposals to replace an existing resolver's result struct with per-source strategy objects when the sources' lifecycles differ.
