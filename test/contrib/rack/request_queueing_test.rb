require 'contrib/rack/helpers'

class RequestQueuingTest < RackBaseTest
  def setup
    super
    # enable request_queueing
    Datadog.configuration[:rack][:request_queuing] = true
  end

  def test_request_queuing_header
    # ensure a queuing Span is created if the header is available
    request_start = (Time.now.utc - 5).to_i
    header 'x-request-start', "t=#{request_start}"
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(2, spans.length)

    rack_span = spans[0]
    frontend_span = spans[1]
    assert_equal('rack.request', rack_span.name)
    assert_equal('request.enqueuing', frontend_span.name)

    assert_equal('http', rack_span.span_type)
    assert_equal('rack', rack_span.service)
    assert_equal('GET 200', rack_span.resource)
    assert_equal('GET', rack_span.get_tag('http.method'))
    assert_equal('200', rack_span.get_tag('http.status_code'))
    assert_equal('/success/', rack_span.get_tag('http.url'))
    assert_equal(0, rack_span.status)
    assert_equal(frontend_span.span_id, rack_span.parent_id)

    assert_equal('web-server', frontend_span.service)
    assert_equal(request_start, frontend_span.start_time.to_i)
  end

  def test_request_alternative_queuing_header
    # ensure a queuing Span is created if the header is available
    request_start = (Time.now.utc - 5).to_i
    header 'x-queue-start', "t=#{request_start}"
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(2, spans.length)

    rack_span = spans[0]
    frontend_span = spans[1]
    assert_equal('rack.request', rack_span.name)
    assert_equal('request.enqueuing', frontend_span.name)

    assert_equal('http', rack_span.span_type)
    assert_equal('rack', rack_span.service)
    assert_equal('GET 200', rack_span.resource)
    assert_equal('GET', rack_span.get_tag('http.method'))
    assert_equal('200', rack_span.get_tag('http.status_code'))
    assert_equal('/success/', rack_span.get_tag('http.url'))
    assert_equal(0, rack_span.status)
    assert_equal(frontend_span.span_id, rack_span.parent_id)

    assert_equal('web-server', frontend_span.service)
    assert_equal(request_start, frontend_span.start_time.to_i)
  end

  def test_request_queuing_service_name
    # ensure a queuing Span is created if the header is available
    Datadog.configuration[:rack][:web_service_name] = 'nginx'
    request_start = (Time.now.utc - 5).to_i
    header 'x-request-start', "t=#{request_start}"
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(2, spans.length)

    rack_span = spans[0]
    frontend_span = spans[1]
    assert_equal('rack.request', rack_span.name)
    assert_equal('request.enqueuing', frontend_span.name)

    assert_equal('nginx', frontend_span.service)
  end

  def test_clock_skew
    # ensure a queuing Span is NOT created if there is a clock skew
    # where the starting time is greater than current host Time.now
    request_start = (Time.now.utc + 5).to_i
    header 'x-request-start', "t=#{request_start}"
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    rack_span = spans[0]
    assert_equal('rack.request', rack_span.name)
  end

  def test_wrong_header
    # ensure a queuing Span is NOT created if the header is wrong
    header 'x-request-start', 'something_weird'
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    rack_span = spans[0]
    assert_equal('rack.request', rack_span.name)
  end

  def test_enabled_missing_header
    # ensure a queuing Span is NOT created if the header is missing
    get '/success/'
    assert last_response.ok?

    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)

    rack_span = spans[0]
    assert_equal('rack.request', rack_span.name)
  end
end
