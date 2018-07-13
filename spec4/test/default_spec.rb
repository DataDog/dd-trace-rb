require('spec_helper')
require('ddtrace')

RSpec.describe Datadog::Tracer do
  it('default tracer') do
    expect(Datadog.tracer.instance_of?(described_class)).to(eq(true))
  end
end
