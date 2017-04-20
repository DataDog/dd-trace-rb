require 'contrib/grape/helpers'

class TracedAPITest < BaseAPITest
  def test_traced_api_200
    get '/success'
    assert last_response.ok?
    assert_equal('OK', last_response.body)

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)

    span = spans[0]
    assert_equal('grape.endpoint_run', span.name)
    assert_equal('http', span.span_type)
    assert_equal('grape', span.service)
    assert_equal('TestingAPI#success', span.resource)
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end
end
