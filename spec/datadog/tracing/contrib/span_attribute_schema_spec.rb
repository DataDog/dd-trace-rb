require 'datadog/tracing/contrib/span_attribute_schema'

RSpec.describe Datadog::Tracing::Contrib::SpanAttributeSchema do
  describe '#default_span_attribute_schema?' do
    context 'when default schema is set' do
      it 'returns true' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.default_span_attribute_schema?).to eq(true)
        end
      end
    end

    context 'when default schema is changed' do
      it 'returns false' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.default_span_attribute_schema?).to eq(false)
        end
      end
    end

    context 'when default schema is not set' do
      it 'returns true' do
        expect(described_class.default_span_attribute_schema?).to eq(true)
      end
    end
  end

  describe '#fetch_service_name' do
    context 'when integration service is set' do
      it 'returns the integration specific service name' do
        with_modified_env DD_INTEGRATION_SERVICE: 'integration-service-name' do
          expect(
            described_class
                          .fetch_service_name('DD_INTEGRATION_SERVICE',
                            'default-integration-service-name')
          ).to eq('integration-service-name')
        end
      end
    end

    context 'when integration service is not set' do
      context 'when v1 schema is set' do
        context 'when DD_SERVICE is set' do
          it 'returns DD_SERVICE' do
            with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1', DD_SERVICE: 'service' do
              expect(
                described_class
                                  .fetch_service_name('DD_INTEGRATION_SERVICE',
                                    'default-integration-service-name')
              ).to eq('service')
            end
          end
        end

        context 'when DD_SERVICE is not set' do
          it 'returns default program name' do
            with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
              expect(
                described_class
                                  .fetch_service_name('DD_INTEGRATION_SERVICE',
                                    'default-integration-service-name')
              ).to eq('rspec')
            end
          end
        end
      end

      context 'when v0 schema is set' do
        it 'returns default integration service name' do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0', DD_SERVICE: 'service' do
            expect(
              described_class
                              .fetch_service_name('DD_INTEGRATION_SERVICE',
                                'default-integration-service-name')
            ).to eq('default-integration-service-name')
          end
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
