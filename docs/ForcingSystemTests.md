# Forcing System Tests

During development, you may want to force-execute specific system-tests on dd-trace-rb CI while their declaration aren't merged yet on system-tests side.
To do so, you can complete the `.github/forced-tests-list.json` file by following this template:

```json
{
  "SYSTEM_TEST_SCENARIO_1":
    [
      "tests/test_forced_file.py",
      "tests/test_forced_file.py::Test_ForcedClass",
      "tests/test_forced_file.py::Test_ForcedClass::test_forced_method"
    ],
  "SYSTEM_TEST_SCENARIO_2":
    [
      ...
    ],
    ...
}
```

## Example

```json
{
  "DEFAULT":
    [
      "tests/appsec/waf/test_miscs.py::Test_CorrectOptionProcessing",
      "tests/test_semantic_conventions.py::Test_Meta::test_meta_span_kind"
    ],
  "APPSEC_STANDALONE":
    [
      "tests/appsec/test_asm_standalone.py"
    ]
}
```

## Cleanup

You can leave other force-executed tests added by other developers and append yours to the .json file, there is a cleanup task in the release process.

## Reference

System-tests documentation on [force-executing tests](https://github.com/DataDog/system-tests/blob/main/docs/execute/force-execute.md)