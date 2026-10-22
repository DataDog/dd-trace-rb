<!-- expect: -->
### Why

Fixes failures, e.g. crashes, on Rails 7. Two-way door.

### What

The clock in `serializer.rb` reads thread CPU time (see [the docs](https://example.com/docs)). Scoped to DI.

### Risk

Two-way door, scoped to `serializer.rb`. Revert restores the old clock.
