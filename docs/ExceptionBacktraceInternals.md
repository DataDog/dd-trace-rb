# Exception Backtrace Internals: Why UnboundMethod Bypasses `backtrace_locations` Overrides But Not `backtrace` Overrides

This document explains a MRI implementation detail that affects how
`Datadog::DI::EXCEPTION_BACKTRACE_LOCATIONS` and `Datadog::DI::EXCEPTION_BACKTRACE`
work when exception subclasses override backtrace methods.

## Background

DI captures `Exception.instance_method(:backtrace_locations)` and
`Exception.instance_method(:backtrace)` as UnboundMethod constants at load time.
The intent is to call `bind(exception).call` to get the real backtrace without
dispatching through the exception's method table, bypassing subclass overrides.

This works for `backtrace_locations` but **not** for `backtrace`. The reason is
not in how UnboundMethod dispatches — both correctly call the C function — but in
what MRI's `raise` stores on the exception object beforehand.

## How MRI Stores Backtraces During `raise`

When Ruby executes `raise`, it calls `setup_exception` (eval.c), which decides
whether to store the VM's backtrace on the exception:

```c
// eval.c — setup_exception (simplified)
VALUE bt = rb_get_backtrace(mesg);   // ← checks for #backtrace override
if (NIL_P(bt)) {
    VALUE at = rb_ec_backtrace_object(ec);
    rb_ivar_set(mesg, idBt_locations, at);  // store in @bt_locations
    set_backtrace(mesg, at);                // store in @bt
}
```

`rb_get_backtrace` (error.c) checks whether `#backtrace` — specifically
`#backtrace`, not `#backtrace_locations` — has been overridden:

```c
// error.c — rb_get_backtrace (simplified)
if (rb_method_basic_definition_p(CLASS_OF(exc), id_backtrace)) {
    info = exc_backtrace(exc);           // no override → C function
} else {
    info = rb_funcallv(exc, mid, 0, 0);  // override → call it
}
```

The logic: if the exception already "has" a backtrace (the override returned
non-nil), don't overwrite it with the VM's backtrace. This means:

- **Override `backtrace`** → `rb_get_backtrace` calls the override → gets non-nil
  → `NIL_P(bt)` is false → real backtrace **never stored** in `@bt` or
  `@bt_locations`.

- **Override `backtrace_locations`** (but not `backtrace`) → `rb_get_backtrace`
  finds no override of `backtrace` → calls `exc_backtrace` → `@bt` is nil
  (initialized to nil by `exc_init`) → returns nil → `NIL_P(bt)` is true → real
  backtrace **stored** in both `@bt` and `@bt_locations`.

## What the C Functions Read

Both `exc_backtrace` and `exc_backtrace_locations` are simple ivar readers:

```c
// error.c
static VALUE exc_backtrace(VALUE exc) {
    VALUE obj = rb_attr_get(exc, id_bt);        // reads @bt
    if (rb_backtrace_p(obj))
        obj = rb_backtrace_to_str_ary(obj);     // convert raw → strings
    return obj;
}

static VALUE exc_backtrace_locations(VALUE exc) {
    VALUE obj = rb_attr_get(exc, id_bt_locations);  // reads @bt_locations
    if (!NIL_P(obj))
        obj = rb_backtrace_to_location_ary(obj);    // convert raw → Locations
    return obj;
}
```

When called via UnboundMethod, these C functions execute correctly — the dispatch
is not the problem. The problem is that the ivars they read may be empty because
`setup_exception` never populated them.

## Demonstration

### Override `backtrace_locations` only — UnboundMethod bypasses it

```ruby
BT      = Exception.instance_method(:backtrace)
BT_LOCS = Exception.instance_method(:backtrace_locations)

class OverrideLocations < StandardError
  def backtrace_locations; []; end
end

e = begin; raise OverrideLocations, "test"; rescue => e; e; end
```

During `raise`:
1. `rb_get_backtrace` checks for `#backtrace` override → **none found**
2. Calls `exc_backtrace` → `@bt` is nil → returns nil
3. `NIL_P(bt)` is true → **stores real backtrace** in `@bt` and `@bt_locations`

After `raise`:

```ruby
e.backtrace_locations         #=> []         (Ruby override)
BT_LOCS.bind(e).call.first   #=> #<Thread::Backtrace::Location> (real backtrace from @bt_locations)
BT.bind(e).call.first         #=> "example.rb:8:in '<main>'"    (real backtrace from @bt)
```

Both UnboundMethod calls return real data because `setup_exception` stored it.

### Override `backtrace` only — UnboundMethod returns nil

```ruby
class OverrideBacktrace < StandardError
  def backtrace; ["fake:0:in 'fake'"]; end
end

e = begin; raise OverrideBacktrace, "test"; rescue => e; e; end
```

During `raise`:
1. `rb_get_backtrace` checks for `#backtrace` override → **found**
2. Calls the override → gets `["fake:0:in 'fake'"]` (non-nil)
3. `NIL_P(bt)` is false → **skips storing** → `@bt` stays nil, `@bt_locations` stays nil

After `raise`:

```ruby
e.backtrace                   #=> ["fake:0:in 'fake'"] (Ruby override)
BT.bind(e).call               #=> nil                  (@bt was never populated)
BT_LOCS.bind(e).call          #=> nil                  (@bt_locations was never populated)
```

Both UnboundMethod calls return nil. The real backtrace was never stored.

### Override both — UnboundMethod returns nil for both

```ruby
class OverrideBoth < StandardError
  def backtrace;           ["fake:0:in 'fake'"]; end
  def backtrace_locations; [];                    end
end

e = begin; raise OverrideBoth, "test"; rescue => e; e; end
```

During `raise`:
1. `rb_get_backtrace` checks for `#backtrace` override → **found**
2. Calls the override → non-nil → skips storing

After `raise`:

```ruby
e.backtrace                   #=> ["fake:0:in 'fake'"] (override)
e.backtrace_locations         #=> []                    (override)
BT.bind(e).call               #=> nil                  (not stored)
BT_LOCS.bind(e).call          #=> nil                  (not stored)
```

Same as overriding `backtrace` alone — `rb_get_backtrace` only checks
`#backtrace`, so adding a `#backtrace_locations` override changes nothing
about what `setup_exception` stores.

### `set_backtrace` with strings — no override, UnboundMethod works for `backtrace`

```ruby
e = StandardError.new("wrapped")
e.set_backtrace(["/app/foo.rb:10:in 'bar'"])
```

No `raise` involved, so `setup_exception` never runs. `set_backtrace` (error.c)
stores the string array directly in `@bt`:

```c
// error.c — exc_set_backtrace (simplified)
btobj = rb_location_ary_to_backtrace(bt);
if (RTEST(btobj)) {
    rb_ivar_set(exc, id_bt, btobj);            // Location array
    rb_ivar_set(exc, id_bt_locations, btobj);
} else {
    rb_ivar_set(exc, id_bt, rb_check_backtrace(bt));  // string array → @bt only
}
```

String arrays go into `@bt` only (not `@bt_locations`):

```ruby
BT.bind(e).call               #=> ["/app/foo.rb:10:in 'bar'"]  (reads @bt)
BT_LOCS.bind(e).call          #=> nil                           (@bt_locations not set)
```

This is the case DI's fallback path handles: `backtrace_locations` returns nil
(triggering the fallback), then `backtrace` returns the string array (which we
parse with a regex).

## Summary Table

| Scenario | `@bt` | `@bt_locations` | UnboundMethod `backtrace` | UnboundMethod `backtrace_locations` |
|---|---|---|---|---|
| No override | real backtrace | real backtrace | real strings | real Locations |
| Override `backtrace_locations` only | real backtrace | real backtrace | real strings | real Locations |
| Override `backtrace` only | nil | nil | nil | nil |
| Override both | nil | nil | nil | nil |
| `set_backtrace` with strings | string array | nil | string array | nil |
| `set_backtrace` with Locations (Ruby 3.4+) | Location array | Location array | real strings | real Locations |

## Implications for DI

DI uses `EXCEPTION_BACKTRACE_LOCATIONS` as the primary path and
`EXCEPTION_BACKTRACE` as a fallback for when `backtrace_locations` returns nil
(the `set_backtrace` with strings case).

The limitation — that overriding `#backtrace` prevents both UnboundMethod calls
from working — does not affect DI in practice:

1. The primary path (`backtrace_locations` via UnboundMethod) handles the common
   case: exceptions raised normally, possibly with `backtrace_locations` overridden.

2. The fallback path (`backtrace` via UnboundMethod) handles the `set_backtrace`
   with strings case, where no subclass override is involved.

3. The gap is: a subclass that overrides `#backtrace` AND whose instance had
   `set_backtrace` called with strings. In this case, both paths return nil and
   DI reports an empty stacktrace. This combination is extremely unlikely in
   practice, and the exception type and message are still reported.
