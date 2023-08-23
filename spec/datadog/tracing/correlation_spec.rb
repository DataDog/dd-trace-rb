require 'spec_helper'

require 'datadog/core'
require 'datadog/tracing/correlation'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Correlation do
  let(:default_env) { 'default-env' }
  let(:default_service) { 'default-service' }
  let(:default_version) { 'default-version' }

  before do
    settings = Datadog.configuration
    allow(settings).to receive(:env).and_return(default_env)
    allow(settings).to receive(:service).and_return(default_service)
    allow(settings).to receive(:version).and_return(default_version)
  end

  shared_context 'correlation data' do
    let(:env) { 'dev' }
    let(:service) { 'acme-api' }
    let(:span_id) { Datadog::Tracing::Utils.next_id }
    let(:span_name) { 'active_record.sql' }
    let(:span_resource) { 'SELECT * FROM users;' }
    let(:span_service) { 'acme-mysql' }
    let(:span_type) { 'db' }
    let(:trace_id) { Datadog::Tracing::Utils.next_id }
    let(:trace_name) { 'rack.request' }
    let(:trace_resource) { 'GET /users' }
    let(:trace_service) { 'acme-api' }
    let(:version) { '0.1' }
  end

  describe '::identifier_from_digest' do
    subject(:identifier_from_digest) { described_class.identifier_from_digest(digest) }
    let(:identifier) { identifier_from_digest }

    context 'given nil' do
      let(:digest) { nil }

      it { is_expected.to be_a_kind_of(described_class::Identifier) }

      it do
        expect(identifier).to have_attributes(
          env: default_env,
          service: default_service,
          span_id: 0,
          span_name: nil,
          span_resource: nil,
          span_service: nil,
          span_type: nil,
          trace_id: 0,
          trace_name: nil,
          trace_resource: nil,
          trace_service: nil,
          version: default_version
        )
      end

      it 'has frozen copies of strings' do
        expect(identifier.env).to be_a_frozen_copy_of(default_env)
        expect(identifier.service).to be_a_frozen_copy_of(default_service)
        expect(identifier.version).to be_a_frozen_copy_of(default_version)
      end
    end

    context 'given a TraceDigest object' do
      include_context 'correlation data'

      let(:digest) do
        instance_double(
          Datadog::Tracing::TraceDigest,
          span_id: span_id,
          span_name: span_name,
          span_resource: span_resource,
          span_service: span_service,
          span_type: span_type,
          trace_id: trace_id,
          trace_name: trace_name,
          trace_resource: trace_resource,
          trace_service: trace_service
        )
      end

      it do
        expect(identifier).to have_attributes(
          env: default_env,
          service: default_service,
          span_id: span_id,
          span_name: span_name,
          span_resource: span_resource,
          span_service: span_service,
          span_type: span_type,
          trace_id: trace_id,
          trace_name: trace_name,
          trace_resource: trace_resource,
          trace_service: trace_service,
          version: default_version
        )
      end

      it 'has frozen copies of strings' do
        expect(identifier.env).to be_a_frozen_copy_of(default_env)
        expect(identifier.service).to be_a_frozen_copy_of(default_service)
        expect(identifier.span_name).to be_a_frozen_copy_of(span_name)
        expect(identifier.span_resource).to be_a_frozen_copy_of(span_resource)
        expect(identifier.span_service).to be_a_frozen_copy_of(span_service)
        expect(identifier.span_type).to be_a_frozen_copy_of(span_type)
        expect(identifier.trace_name).to be_a_frozen_copy_of(trace_name)
        expect(identifier.trace_resource).to be_a_frozen_copy_of(trace_resource)
        expect(identifier.trace_service).to be_a_frozen_copy_of(trace_service)
        expect(identifier.version).to be_a_frozen_copy_of(default_version)
      end
    end
  end

  describe described_class::Identifier do
    describe '#new' do
      context 'given no arguments' do
        subject(:identifier) { described_class.new }

        it do
          expect(identifier).to have_attributes(
            env: default_env,
            service: default_service,
            span_id: 0,
            span_name: nil,
            span_resource: nil,
            span_service: nil,
            span_type: nil,
            trace_id: 0,
            trace_name: nil,
            trace_resource: nil,
            trace_service: nil,
            version: default_version
          )
        end

        it 'has frozen copies of strings' do
          expect(identifier.env).to be_a_frozen_copy_of(default_env)
          expect(identifier.service).to be_a_frozen_copy_of(default_service)
          expect(identifier.version).to be_a_frozen_copy_of(default_version)
        end
      end

      context 'given full arguments' do
        include_context 'correlation data'

        subject(:identifier) do
          described_class.new(
            env: env,
            service: service,
            span_id: span_id,
            span_name: span_name,
            span_resource: span_resource,
            span_service: span_service,
            span_type: span_type,
            trace_id: trace_id,
            trace_name: trace_name,
            trace_resource: trace_resource,
            trace_service: trace_service,
            version: version
          )
        end

        it do
          expect(identifier).to have_attributes(
            env: env,
            service: service,
            span_id: span_id,
            span_name: span_name,
            span_resource: span_resource,
            span_service: span_service,
            span_type: span_type,
            trace_id: trace_id,
            trace_name: trace_name,
            trace_resource: trace_resource,
            trace_service: trace_service,
            version: version
          )
        end

        it 'has frozen copies of strings' do
          expect(identifier.env).to be_a_frozen_copy_of(env)
          expect(identifier.service).to be_a_frozen_copy_of(service)
          expect(identifier.span_name).to be_a_frozen_copy_of(span_name)
          expect(identifier.span_resource).to be_a_frozen_copy_of(span_resource)
          expect(identifier.span_service).to be_a_frozen_copy_of(span_service)
          expect(identifier.span_type).to be_a_frozen_copy_of(span_type)
          expect(identifier.trace_name).to be_a_frozen_copy_of(trace_name)
          expect(identifier.trace_resource).to be_a_frozen_copy_of(trace_resource)
          expect(identifier.trace_service).to be_a_frozen_copy_of(trace_service)
          expect(identifier.version).to be_a_frozen_copy_of(version)
        end
      end
    end

    describe '#to_h' do
      context 'when given values' do
        let(:trace_id) { Datadog::Tracing::Utils.next_id }
        let(:span_id) { Datadog::Tracing::Utils.next_id }

        it 'returns a formatted hash' do
          identifier = described_class.new(
            env: 'dev',
            service: 'acme-api',
            version: '1.0',
            span_id: span_id,
            trace_id: trace_id,
          )

          expect(identifier.to_h).to eq(
            {
              dd: {
                env: 'dev',
                service: 'acme-api',
                version: '1.0',
                trace_id: trace_id.to_s,
                span_id: span_id.to_s
              },
              ddsource: 'ruby'
            }
          )
        end
      end

      context 'when given `nil`' do
        it 'returns a formatted hash with default values' do
          identifier = described_class.new(
            env: nil,
            service: nil,
            version: nil,
            span_id: nil,
            trace_id: nil,
          )

          expect(identifier.to_h).to eq(
            {
              dd: {
                env: 'default-env',
                service: 'default-service',
                version: 'default-version',
                trace_id: '0',
                span_id: '0',
              },
              ddsource: 'ruby'
            }
          )
        end
      end
    end

    describe '#to_log_format' do
      shared_examples_for 'a log format string' do
        subject(:string) { identifier.to_log_format }

        let(:identifier) do
          described_class.new(
            env: env,
            service: service,
            span_id: span_id,
            trace_id: trace_id,
            version: version,
          )
        end

        let(:trace_id) { Datadog::Tracing::Utils.next_id }
        let(:span_id) { Datadog::Tracing::Utils.next_id }
        let(:env) { 'dev' }
        let(:service) { 'acme-api' }
        let(:version) { '1.0' }

        it 'doesn\'t have attributes without values' do
          is_expected.to_not match(/.*=(?=\z|\s)/)
        end

        RSpec::Matchers.define :be_serialized_nested_hash do |expected|
          match do |actual|
            result = expected.each_with_object(String.new) do |(key, value), string|
              if value.is_a? Hash
                value.each_pair { |k, v| string << "#{key}.#{k}=#{v} " unless v.empty? }
              else
                string << "#{key}=#{value} "
              end
            end.strip!

            actual == result
          end
        end

        it 'serializes a nested hash' do
          is_expected.to be_serialized_nested_hash(identifier.to_h)
        end
      end

      # Expect string to contain the attribute, at the beginning/end of the string,
      # or buffered by a whitespace character to delimit it.
      def have_attribute(attribute)
        match(/(?<=\A|\s)#{Regexp.escape(attribute)}(?=\z|\s)/)
      end

      context 'when #trace_id' do
        context 'is defined' do
          context 'when 128 bit trace id logging is not enabled' do
            before do
              allow(Datadog.configuration.tracing).to receive(:trace_id_128_bit_logging_enabled).and_return(false)
            end

            context 'when given 64 bit trace id' do
              it_behaves_like 'a log format string' do
                let(:trace_id) { 0xaaaaaaaaaaaaaaaa }
                let(:expected_trace_id) { trace_id }
                it do
                  is_expected.to have_attribute(
                    "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_TRACE_ID}=#{expected_trace_id}"
                  )
                end
              end
            end

            context 'when given 128 bit trace id' do
              it_behaves_like 'a log format string' do
                let(:trace_id) { 0xaaaaaaaaaaaaaaaaffffffffffffffff }
                let(:expected_trace_id) { 0xffffffffffffffff }
                it do
                  is_expected.to have_attribute(
                    "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_TRACE_ID}=#{expected_trace_id}"
                  )
                end
              end
            end
          end

          context 'when 128 bit trace id logging is enabled' do
            before do
              allow(Datadog.configuration.tracing).to receive(:trace_id_128_bit_logging_enabled).and_return(true)
            end

            context 'when given 64 bit trace id' do
              it_behaves_like 'a log format string' do
                let(:trace_id) { 0xaaaaaaaaaaaaaaaa }
                let(:expected_trace_id) { trace_id }
                it do
                  is_expected.to have_attribute(
                    "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_TRACE_ID}=#{expected_trace_id}"
                  )
                end
              end
            end

            context 'when given > 64 bit trace id' do
              it_behaves_like 'a log format string' do
                let(:trace_id) { 0xffffffffffffffffaaaaaaaaaaaaaaaa }
                let(:expected_trace_id) { trace_id }

                it do
                  is_expected.to have_attribute(
                    "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_TRACE_ID}=ffffffffffffffffaaaaaaaaaaaaaaaa"
                  )
                end
              end
            end
          end

          context 'when given > 64 bit trace id but high order is 0' do
            it_behaves_like 'a log format string' do
              let(:trace_id) { 0x00000000000000000aaaaaaaaaaaaaaaa }
              let(:expected_trace_id) { trace_id }

              it do
                is_expected.to have_attribute(
                  "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_TRACE_ID}=#{expected_trace_id}"
                )
              end
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'a log format string' do
            let(:trace_id) { nil }
            it do
              is_expected.to have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_TRACE_ID}=0"
              )
            end
          end
        end
      end

      context 'when #span_id' do
        context 'is defined' do
          it_behaves_like 'a log format string' do
            let(:span_id) { Datadog::Tracing::Utils.next_id }
            it do
              is_expected.to have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_SPAN_ID}=#{span_id}"
              )
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'a log format string' do
            let(:span_id) { nil }
            it do
              is_expected.to have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_SPAN_ID}=0"
              )
            end
          end
        end
      end

      context 'when #env' do
        context 'is defined' do
          it_behaves_like 'a log format string' do
            let(:env) { 'dev' }
            it do
              is_expected.to have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_ENV}=#{env}"
              )
            end

            it 'puts the env attribute before trace ID and span ID' do
              is_expected.to match(/(dd\.env=).*(dd\.trace_id=).*(dd\.span_id=).*/)
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'a log format string' do
            let(:env) { nil }
            it do
              is_expected.to_not have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_ENV}=#{env}"
              )
            end
          end
        end
      end

      context 'when #service' do
        context 'is defined' do
          it_behaves_like 'a log format string' do
            let(:service) { 'acme-api' }
            it do
              is_expected.to have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_SERVICE}=#{service}"
              )
            end

            it 'puts the service attribute before trace ID and span ID' do
              is_expected.to match(/(dd\.service=).*(dd\.trace_id=).*(dd\.span_id=).*/)
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'a log format string' do
            let(:service) { nil }
            it do
              is_expected.to_not have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_SERVICE}=#{service}"
              )
            end
          end
        end
      end

      context 'when #version' do
        context 'is defined' do
          it_behaves_like 'a log format string' do
            let(:version) { '0.1' }
            it do
              is_expected.to have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_VERSION}=#{version}"
              )
            end

            it 'puts the version attribute before trace ID and span ID' do
              is_expected.to match(/(dd\.version=).*(dd\.trace_id=).*(dd\.span_id=).*/)
            end
          end
        end

        context 'is not defined' do
          it_behaves_like 'a log format string' do
            let(:version) { nil }
            it do
              is_expected.to_not have_attribute(
                "#{Datadog::Tracing::Correlation::Identifier::LOG_ATTR_VERSION}=#{version}"
              )
            end
          end
        end
      end
    end

    describe '#trace_id' do
      context 'is defined' do
        context 'when 128 bit trace id logging is not enabled' do
          before do
            allow(Datadog.configuration.tracing).to receive(:trace_id_128_bit_logging_enabled).and_return(false)
          end

          context 'when given 64 bit trace id' do
            it 'returns to lower 64 bits of trace id' do
              trace_id = 0xaaaaaaaaaaaaaaaa
              expected_trace_id = 0xaaaaaaaaaaaaaaaa

              identifier = described_class.new(trace_id: trace_id)

              expect(identifier.trace_id).to eq(expected_trace_id)
            end
          end

          context 'when given 128 bit trace id' do
            it 'returns to lower 64 bits of trace id' do
              trace_id = 0xaaaaaaaaaaaaaaaaffffffffffffffff
              expected_trace_id = 0xffffffffffffffff

              identifier = described_class.new(trace_id: trace_id)

              expect(identifier.trace_id).to eq(expected_trace_id)
            end
          end
        end

        context 'when 128 bit trace id logging is enabled' do
          before do
            allow(Datadog.configuration.tracing).to receive(:trace_id_128_bit_logging_enabled).and_return(true)
          end

          context 'when given 64 bit trace id' do
            it 'returns lower 64 bits of trace id' do
              trace_id = 0xaaaaaaaaaaaaaaaa
              expected_trace_id = 0xaaaaaaaaaaaaaaaa

              identifier = described_class.new(trace_id: trace_id)

              expect(identifier.trace_id).to eq(expected_trace_id)
            end
          end

          context 'when given > 64 bit trace id' do
            it 'returns the entire trace id in hex encoded and zero padded format' do
              trace_id = 0x00ffffffffffffffaaaaaaaaaaaaaaaa

              identifier = described_class.new(trace_id: trace_id)

              expect(identifier.trace_id).to eq('00ffffffffffffffaaaaaaaaaaaaaaaa')
            end
          end
        end

        context 'when given > 64 bit trace id but high order is 0' do
          it 'returns to lower 64 bits of trace id' do
            trace_id = 0x00000000000000000aaaaaaaaaaaaaaaa
            expected_trace_id = 0xaaaaaaaaaaaaaaaa

            identifier = described_class.new(trace_id: trace_id)

            expect(identifier.trace_id).to eq(expected_trace_id)
          end
        end
      end
    end
  end
end
