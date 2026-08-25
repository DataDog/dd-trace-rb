# Hooks Guide

This is a short guide explaining code organization and conventions. For the
complete Claude hooks documentation please follow the [official documentation]

## Code organization

```text
.claude/
├── settings.json        <-- hooks registration
└── hooks/
    ├── Makefile         <-- the hook compilation and tests
    ├── <name>.rb        <-- the hook code
    ├── <name>.test.rb   <-- the hook tests
    ├── shims/
    │   └── <name>       <-- the file used in a settings as a hook script
    └── compiled/
        └── <name>       <-- the hook code as compiled binary (optional)
```

For simplicity of development and maintenance each hook is written and tested
in Ruby. The **hook is a single file** that is self-contained and doesn't have any
external dependency (at least for now)

The hook **tests are also a single file** that represents _unit_ tests and _smoke_
(integration) tests. To avoid bloating for a relative simple matter, both unit and
smoke tests co-live in the same test file

Each hook exposes an _executable_ shim-file that is encapsulates knowledge about
optional compiled binary file. And the compiled binary is stored under `compiled/`
folder under the same name

> [!IMPORTANT]
> Do not use `.rb` file in the settings directly, point to the `shim` that will
> handle pure Ruby and optionally compiled hook binary

For binary compilation [Spinel] is used, but be aware that **not all Ruby features
and methods are currently supported** and that might require you to adjust your
script

> [!NOTE]
> Currently there is no shared library for hooks, but if it will emerge, shared
> files should be isolated from the root folder in `lib/` or similar folder

## Naming conventions

For the hook name a simple framework is suggested: a dash-separated verb (or action)
and a subject, for instance: `require-skill`, `load-file`, `reject-read`

## Tests

Right now `Test::Unit` is the default testing framework used for both Ruby and
compiled binary testing.

The logic behind the smoke tests is the following: for the same input the `.rb`
file and compiled binary must produce the same output, with the `.rb` file acting
as the reference implementation.

To run all tests execute

```console
.claude/hooks$ make test
```

and to test a single hook, you can run the following

```console
.claude/hooks$ ruby <name>.test.rb
```

> [!IMPORTANT]
> Running a single test file directly does not recompile the binary. Run `make test`
> after changing hook code to verify both implementations

[official documentation]: https://code.claude.com/docs/en/hooks
[Spinel]: https://github.com/matz/spinel
