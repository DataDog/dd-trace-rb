require 'ddtrace'
require 'sequel'

Datadog::Monkey.patch_module(:sequel)
