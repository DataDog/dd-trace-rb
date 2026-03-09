# Error Handling in Symbol Database

See PR comment for full analysis.

## Summary

**Principle:** No exceptions to customer applications.

**Pattern:**
- Public entry points: MUST rescue (Component.start_upload, Uploader.upload_scopes, ScopeContext.add_scope)
- Internal utilities: Rescue and return nil/empty (FileHash, Extractor methods)
- Data models: Can raise ArgumentError (internal use, caught by callers)

**Issues Found:**
1. Bare `rescue` in 3 places (should be `rescue StandardError`)
2. Some double rescues (redundant)
3. Need mutex for start_upload (concurrency)
4. Need in-flight upload tracking for shutdown

**Fixes:** See PR feedback and subsequent commits.
