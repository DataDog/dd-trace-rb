require 'ddtrace'
require 'redis'
require 'hiredis'

Datadog.configure do |c|
  c.use :redis
end
