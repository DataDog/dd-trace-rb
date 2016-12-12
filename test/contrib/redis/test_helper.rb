require 'redis'
require 'hiredis'
require 'ddtrace/monkey'

Datadog::Monkey.patch_all
