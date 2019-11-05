require 'spec_helper'

require 'ddtrace/sampling/rule'

RSpec.describe Datadog::Sampling::SimpleRule do
  let(:span) { Datadog::Span.new(nil, span_name, service: span_service) }
  let(:span_name) { 'operation.name' }
  let(:span_service) { nil }

  describe '#sample' do
    subject(:sample) { rule.sample(span) }

    context 'with a name matcher' do
      let(:rule) { described_class.new(name: name, sampling_rate: 1) }

      context 'with a regexp' do
        let(:name) { // }

        it do
          is_expected.to be_falsey
        end
      end
    end
  end
end