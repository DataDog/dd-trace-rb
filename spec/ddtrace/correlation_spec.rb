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
    let(:environment) { nil }
    let(:version) { nil }

    before do
      allow(Datadog.configuration).to receive(:env).and_return(environment)
      allow(Datadog.configuration).to receive(:version).and_return(version)
    end

    context 'given nil' do
      let(:context) { nil }

      shared_examples_for 'an empty correlation identifier' do
        it { is_expected.to be_a_kind_of(Datadog::Correlation::Identifier) }
        it { expect(correlation_ids.trace_id).to be 0 }
        it { expect(correlation_ids.span_id).to be 0 }
        it { expect(correlation_ids.env).to eq environment }
        it { expect(correlation_ids.version).to eq version }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_TRACE_ID}=0") }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_SPAN_ID}=0") }
      end

      shared_examples_for 'a correlation identifier with DD_ENV' do
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{environment}") }
      end

      shared_examples_for 'a correlation identifier without DD_ENV' do
        it { expect(correlation_ids.to_s).to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{environment}") }
      end

      shared_examples_for 'a correlation identifier with DD_VERSION' do
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
      end

      shared_examples_for 'a correlation identifier without DD_VERSION' do
        it { expect(correlation_ids.to_s).to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
      end

      it_behaves_like 'an empty correlation identifier'

      context 'after Datadog::Environment::env has changed' do
        let(:environment) { 'my-env' }
        it_behaves_like 'an empty correlation identifier'
        it_behaves_like 'a correlation identifier with DD_ENV'
        it_behaves_like 'a correlation identifier without DD_VERSION'
      end

      context 'after Datadog::Environment::version has changed' do
        let(:version) { 'my-version' }
        it_behaves_like 'an empty correlation identifier'
        it_behaves_like 'a correlation identifier without DD_ENV'
        it_behaves_like 'a correlation identifier with DD_VERSION'
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
        it { expect(correlation_ids.env).to eq environment }
        it { expect(correlation_ids.version).to eq version }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_TRACE_ID}=#{trace_id}") }
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_SPAN_ID}=#{span_id}") }
      end

      shared_examples_for 'a correlation identifier with DD_ENV' do
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{environment}") }
      end

      shared_examples_for 'a correlation identifier without DD_ENV' do
        it { expect(correlation_ids.to_s).to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{environment}") }
      end

      shared_examples_for 'a correlation identifier with DD_VERSION' do
        it { expect(correlation_ids.to_s).to have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
      end

      shared_examples_for 'a correlation identifier without DD_VERSION' do
        it { expect(correlation_ids.to_s).to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
      end

      it_behaves_like 'a correlation identifier with basic properties'

      context 'when #env configuration setting' do
        context 'is not defined' do
          let(:environment) { nil }
          it_behaves_like 'a correlation identifier with basic properties'
          it_behaves_like 'a correlation identifier without DD_ENV'
          it_behaves_like 'a correlation identifier without DD_VERSION'
        end

        context 'is defined' do
          let(:environment) { 'my-env' }
          it_behaves_like 'a correlation identifier with basic properties'
          it_behaves_like 'a correlation identifier with DD_ENV'
          it_behaves_like 'a correlation identifier without DD_VERSION'
        end
      end

      context 'when #version configuration setting' do
        context 'is not defined' do
          let(:version) { nil }
          it_behaves_like 'a correlation identifier with basic properties'
          it_behaves_like 'a correlation identifier without DD_ENV'
          it_behaves_like 'a correlation identifier without DD_VERSION'
        end

        context 'is defined' do
          let(:version) { 'my-version' }
          it_behaves_like 'a correlation identifier with basic properties'
          it_behaves_like 'a correlation identifier without DD_ENV'
          it_behaves_like 'a correlation identifier with DD_VERSION'
        end
      end
    end
  end
end
