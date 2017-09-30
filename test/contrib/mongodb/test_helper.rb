require 'ddtrace'
require 'mongo'

Datadog::Monkey.patch_module(:mongo)
