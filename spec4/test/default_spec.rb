require('helper')
require('ddtrace')
class TracerTest < Minitest::Test
  it('default tracer') do
    expect(Datadog.tracer.instance_of?(Datadog::Tracer)).to(eq(true))
  end
end
