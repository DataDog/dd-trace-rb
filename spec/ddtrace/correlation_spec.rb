require 'spec_helper'

require 'ddtrace/correlation'
require 'ddtrace/context'

RSpec.describe Datadog::Correlation do
  # Expect string to contain the attribute, at the beginning/end of the string,
  # or buffered by a whitespace character to delimit it.
  def have_attribute(attribute)
    match(/(?<=\A|\s)#{Regexp.escape(attribute)}(?=\z|\s)/)
  end

  describe '::identifier_from_context' do
    subject(:correlation_ids) { described_class.identifier_from_context(context) }

    context 'given nil' do
      let(:context) { nil }

      shared_examples_for 'an empty correlation identifier' do
        it { is_expected.to be_a_kind_of(Datadog::Correlation::Identifier) }
        it { expect(correlation_ids.trace_id).to be 0 }
        it { expect(correlation_ids.span_id).to be 0 }
        it { expect(correlation_ids.to_s).to have_attribute('dd.trace_id=0') }
        it { expect(correlation_ids.to_s).to have_attribute('dd.span_id=0') }
      end

      it_behaves_like 'an empty correlation identifier'

      context 'after Datadog::Environment::env has changed' do
        let(:environment) { 'my-env' }
        before { allow(Datadog::Environment).to receive(:env).and_return(environment) }

        it { expect(correlation_ids.env).to eq environment }
        it { expect(correlation_ids.to_s).to have_attribute("dd.env=#{environment}") }
        it_behaves_like 'an empty correlation identifier'
      end
    end

    context 'given a Context object' do
      let(:context) do
        instance_double(
          Datadog::Context,
          trace_id: trace_id,
          span_id: span_id
        )
      end

      let(:trace_id) { double('trace id') }
      let(:span_id) { double('span id') }

      it 'returns a Correlation::Identifier matching the Context' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(correlation_ids.trace_id).to eq(trace_id)
        expect(correlation_ids.span_id).to eq(span_id)
        expect(correlation_ids.to_s).to eq("dd.trace_id=#{trace_id} dd.span_id=#{span_id}")
      end

      context 'when Datadog::Environment.env' do
        before { allow(Datadog::Environment).to receive(:env).and_return(environment) }

        context 'is not defined' do
          let(:environment) { nil }
          it { expect(correlation_ids.env).to be nil }
          it { expect(correlation_ids.to_s).to eq("dd.trace_id=#{trace_id} dd.span_id=#{span_id}") }
        end

        context 'is defined' do
          let(:environment) { 'my-env' }
          it { expect(correlation_ids.env).to eq environment }
          it { expect(correlation_ids.to_s).to eq("dd.trace_id=#{trace_id} dd.span_id=#{span_id} dd.env=#{environment}") }
        end
      end
    end
  end
end
