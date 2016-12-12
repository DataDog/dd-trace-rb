require 'ddtrace'
require 'redis'
require 'hiredis'

Datadog::Monkey.patch_all
