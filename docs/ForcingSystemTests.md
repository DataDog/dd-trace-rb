# Forcing System Tests

During development, you may want to force-execute specific system-tests on dd-trace-rb CI while their declaration aren't merged yet on system-tests side.
To do so, you can complete the `.github/forced-tests-list.cfg` file by adding nodeids, one per line:

## Example

```
tests/appsec/waf/test_miscs.py::Test_CorrectOptionProcessing
tests/test_semantic_conventions.py::Test_Meta::test_meta_span_kind
tests/appsec/test_asm_standalone.py
```

:attention: Once your PR is merged, you MUST activate those tests in system-tests. Otherwise, they will be deactivated during the next release (see below).

## Cleanup

You can leave other force-executed tests added by other developers and append yours to the .cfg file, there is a cleanup task in the release process.

## Reference

System-tests documentation on [force-executing tests](https://github.com/DataDog/system-tests/blob/main/docs/execute/force-execute.md)
