require 'minitest'
require 'minitest/autorun'

require 'tracer'


def get_test_tracer()
  return Datadog::Tracer.new
end
