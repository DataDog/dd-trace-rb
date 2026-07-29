# Generics

Use a generic when a method's output type depends on its input type, or a
container carries elements of a caller-chosen type

## Rules

- SHOULD use a type parameter `[T]` to preserve an input/output relationship
  instead of returning `untyped`
- SHOULD bound the parameter — `[T < Bound]` — when the input must satisfy a
  constraint
- MUST thread the type through the block for a method that yields and returns the
  block's value — `[T] () { () -> T } -> T`
- SHOULD parameterize the generic core types (`Array[T]`, `Enumerable[T]`,
  `Enumerator[T]`, `Hash[K, V]`) rather than leaving their slots `untyped`

## Examples

Say the output is the same type as the input, and bound it when the input must
be an object:

```rbs
# Good — caller gets back exactly what it passed
def dup: [T] (T value) -> T

def replace: [T < Object] (T item) -> T

# Bad — untyped on both ends throws the relationship away
def dup: (untyped value) -> untyped

def replace: (untyped item) -> untyped
```

The same parameter carries the relationship through a block or a collection:

```rbs
# returns whatever the block returns
def synchronize: [T] () { () -> T } -> T

# result type follows the element type
def first: [T] (Array[T] list) -> T?
```

Without the `[T]`, each of these returns `untyped` and loses the relationship —
the same mistake as the Bad above
