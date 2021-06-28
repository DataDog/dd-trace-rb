require 'ddtrace/profiling/ext/opentelemetry_trace_linking'

RSpec.describe Datadog::Profiling::Ext::OpenTelemetryTraceLinking do
  before(:all) do
    skip 'opentelemetry-api not supported on Ruby < 2.5' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')

    require 'opentelemetry-api'
  end

  subject(:trace_linking) { described_class.new }

  describe '#on_start' do
    let(:span) { instance_double(OpenTelemetry::Trace::Span) }
    let(:parent_context) { double('Context') } # rubocop:disable RSpec/VerifiedDoubles

    it 'adds the runtime id as an attribute to a span' do
      expect(span).to receive(:set_attribute).with(Datadog::Ext::Runtime::TAG_ID, Datadog::Runtime::Identity.id)

      trace_linking.on_start(span, parent_context)
    end
  end

  describe '#on_finish' do
    it 'does nothing' do
      trace_linking.on_finish(double('Span')) # rubocop:disable RSpec/VerifiedDoubles
    end
  end

  describe '#force_flush' do
    it do
      expect(trace_linking.force_flush(timeout: double('Timeout'))).to be 0 # rubocop:disable RSpec/VerifiedDoubles
    end
  end

  describe '#shutdown' do
    it do
      expect(trace_linking.shutdown(timeout: double('Timeout'))).to be 0 # rubocop:disable RSpec/VerifiedDoubles
    end
  end
end
