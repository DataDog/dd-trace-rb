require 'spec_helper'

require 'ddtrace/correlation'
require 'ddtrace/context'

RSpec.describe Datadog::Correlation do
  let(:default_env) { 'default-env' }
  let(:default_service) { 'default-service' }
  let(:default_version) { 'default-version' }

  before do
    allow(Datadog.configuration).to receive(:env).and_return(default_env)
    allow(Datadog.configuration).to receive(:service).and_return(default_service)
    allow(Datadog.configuration).to receive(:version).and_return(default_version)
  end

  describe '::identifier_from_context' do
    subject(:identifier_from_context) { described_class.identifier_from_context(context) }

    context 'given nil' do
      let(:context) { nil }

      it { is_expected.to be_a_kind_of(described_class::Identifier) }
      it { expect(identifier_from_context.frozen?).to be true }
      it { expect(identifier_from_context.trace_id).to eq 0 }
      it { expect(identifier_from_context.span_id).to eq 0 }
      it { expect(identifier_from_context.env).to be default_env }
      it { expect(identifier_from_context.service).to be default_service }
      it { expect(identifier_from_context.version).to be default_version }
    end

    context 'given a Context object' do
      let(:context) do
        instance_double(
          Datadog::Context,
          trace_id: trace_id,
          span_id: span_id
        )
      end

      let(:trace_id) { double('trace ID') }
      let(:span_id) { double('span ID') }

      it { is_expected.to be_a_kind_of(described_class::Identifier) }
      it { expect(identifier_from_context.frozen?).to be true }
      it { expect(identifier_from_context.trace_id).to be trace_id }
      it { expect(identifier_from_context.span_id).to be span_id }
      it { expect(identifier_from_context.env).to be default_env }
      it { expect(identifier_from_context.service).to be default_service }
      it { expect(identifier_from_context.version).to be default_version }
    end
  end

  describe described_class::Identifier do
    describe '#new' do
      context 'given no arguments' do
        subject(:identifier) { described_class.new }

        it do
          is_expected.to have_attributes(
            trace_id: 0,
            span_id: 0,
            env: default_env,
            service: default_service,
            version: default_version
          )
        end
      end

      context 'given full arguments' do
        subject(:identifier) do
          described_class.new(
            trace_id,
            span_id,
            env,
            service,
            version
          )
        end

        let(:trace_id) { double('trace_id') }
        let(:span_id) { double('span_id') }
        let(:env) { double('env') }
        let(:service) { double('service') }
        let(:version) { double('version') }

        it do
          is_expected.to have_attributes(
            trace_id: trace_id,
            span_id: span_id,
            env: env,
            service: service,
            version: version
          )
        end
      end
    end

    describe '#to_s' do
      shared_examples_for 'an identifier string' do
        subject(:string) { identifier.to_s }

        let(:identifier) do
          described_class.new(
            trace_id,
            span_id,
            env,
            service,
            version
          )
        end

        let(:trace_id) { double('trace_id') }
        let(:span_id) { double('span_id') }
        let(:env) { double('env') }
        let(:service) { double('service') }
        let(:version) { double('version') }

        it 'doesn\'t have attributes without values' do
          is_expected.to_not match(/.*=(?=\z|\s)/)
        end
      end

      # Expect string to contain the attribute, at the beginning/end of the string,
      # or buffered by a whitespace character to delimit it.
      def have_attribute(attribute)
        match(/(?<=\A|\s)#{Regexp.escape(attribute)}(?=\z|\s)/)
      end

      context 'when #trace_id' do
        context 'is defined' do
          it_behaves_like 'an identifier string' do
            let(:trace_id) { double('trace_id') }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_TRACE_ID}=#{trace_id}") }
          end
        end

        context 'is not defined' do
          it_behaves_like 'an identifier string' do
            let(:trace_id) { nil }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_TRACE_ID}=0") }
          end
        end
      end

      context 'when #span_id' do
        context 'is defined' do
          it_behaves_like 'an identifier string' do
            let(:span_id) { double('span_id') }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_SPAN_ID}=#{span_id}") }
          end
        end

        context 'is not defined' do
          it_behaves_like 'an identifier string' do
            let(:span_id) { nil }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_SPAN_ID}=0") }
          end
        end
      end

      context 'when #env' do
        context 'is defined' do
          it_behaves_like 'an identifier string' do
            let(:env) { double('env') }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{env}") }

            it 'puts the env attribute before trace ID and span ID' do
              is_expected.to match(/(dd\.env=).*(dd\.trace_id=).*(dd\.span_id=).*/)
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'an identifier string' do
            let(:env) { nil }
            it { is_expected.to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_ENV}=#{env}") }
          end
        end
      end

      context 'when #service' do
        context 'is defined' do
          it_behaves_like 'an identifier string' do
            let(:service) { double('service') }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_SERVICE}=#{service}") }

            it 'puts the service attribute before trace ID and span ID' do
              is_expected.to match(/(dd\.service=).*(dd\.trace_id=).*(dd\.span_id=).*/)
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'an identifier string' do
            let(:service) { nil }
            it { is_expected.to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_SERVICE}=#{service}") }
          end
        end
      end

      context 'when #version' do
        context 'is defined' do
          it_behaves_like 'an identifier string' do
            let(:version) { double('version') }
            it { is_expected.to have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }

            it 'puts the version attribute before trace ID and span ID' do
              is_expected.to match(/(dd\.version=).*(dd\.trace_id=).*(dd\.span_id=).*/)
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'an identifier string' do
            let(:version) { nil }
            it { is_expected.to_not have_attribute("#{Datadog::Ext::Correlation::ATTR_VERSION}=#{version}") }
          end
        end
      end
    end
  end
end
