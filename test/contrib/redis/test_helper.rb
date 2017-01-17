require 'ddtrace'
require 'redis'
require 'hiredis'

Datadog::Monkey.patch_module(:redis)
