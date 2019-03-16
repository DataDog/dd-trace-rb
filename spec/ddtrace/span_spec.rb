require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(tracer, 'test.span', options) }
  let(:options) { { context: context } }
  let(:tracer) { get_test_tracer }
  let(:context) { Datadog::Context.new }

  describe '#set_tag' do
    context 'with \'force.keep\' key' do
      before(:each) { span.set_tag('force.keep') }

      it { expect(span.get_tag('force.keep')).to be_nil }
      it { expect(context.sampling_priority).to eq(2) }
    end
  end
end
