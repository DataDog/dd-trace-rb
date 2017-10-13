require 'helper'

require 'contrib/rails/test_helper'

class TracingDefaultServiceTest < ActionController::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
    update_config(:tracer, @tracer)
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'test that a lone span will have rails service picked up' do
    # Manually creating the span and forgetting service on purpose
    @tracer.trace('web.request') do |span|
      span.resource = '/index'
    end

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[0]
    assert_equal('web.request', span.name)
    assert_equal('/index', span.resource, '/index')
    assert_equal('rails-app', span.service, 'service name should reflect this is a Rails application')
  end
end
