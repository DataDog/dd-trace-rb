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
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_TRACE_ID}=0") }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_SPAN_ID}=0") }
      end

      it_behaves_like 'an empty correlation identifier'

      context 'after Datadog::Environment::env has changed' do
        let(:environment) { 'my-env' }
        before { allow(Datadog::Environment).to receive(:env).and_return(environment) }

        it { expect(correlation_ids.env).to eq environment }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{environment}") }
        it_behaves_like 'an empty correlation identifier'
      end

      context 'after Datadog::Environment::version has changed' do
        let(:version) { 'my-version' }
        before { allow(Datadog::Environment).to receive(:version).and_return(version) }

        it { expect(correlation_ids.version).to eq version }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
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

      shared_examples_for 'a correlation identifier with basic properties' do
        it { is_expected.to be_a_kind_of(Datadog::Correlation::Identifier) }
        it { expect(correlation_ids.trace_id).to eq(trace_id) }
        it { expect(correlation_ids.span_id).to eq(span_id) }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_TRACE_ID}=#{trace_id}") }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_SPAN_ID}=#{span_id}") }
      end

      it_behaves_like 'a correlation identifier with basic properties'

      context 'when Datadog::Environment.env' do
        before { allow(Datadog::Environment).to receive(:env).and_return(environment) }

        context 'is not defined' do
          let(:environment) { nil }
          it { expect(correlation_ids.env).to be nil }
          it_behaves_like 'a correlation identifier with basic properties'
        end

        context 'is defined' do
          let(:environment) { 'my-env' }
          it { expect(correlation_ids.env).to eq environment }
          it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{environment}") }
          it_behaves_like 'a correlation identifier with basic properties'
        end
      end

      context 'when Datadog::Environment.version' do
        before { allow(Datadog::Environment).to receive(:version).and_return(version) }

        context 'is not defined' do
          let(:version) { nil }
          it { expect(correlation_ids.version).to be nil }
          it_behaves_like 'a correlation identifier with basic properties'
        end

        context 'is defined' do
          let(:version) { 'my-version' }
          it { expect(correlation_ids.version).to eq version }
          it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
          it_behaves_like 'a correlation identifier with basic properties'
        end
      end
    end
  end
end
