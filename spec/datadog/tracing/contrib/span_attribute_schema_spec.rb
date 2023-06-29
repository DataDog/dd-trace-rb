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

  # Add test return true if env var is true
  describe '#set_peer_service?' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceSpan', parent_id: 0) }
    context 'when peer service is already set' do
      context 'when peer.service does not match span.service' do
        it 'returns false' do
          span.service = 'test-span-service'
          span.set_tag('peer.service', 'test-service')
          expect(span.get_tag('peer.service')).not_to eq(span.service)
          expect(described_class.send(:set_peer_service?, span)).to be false
        end
      end

      context 'when span.service does not equal global service' do
        it 'returns false' do
          span.service = 'test-service'
          span.set_tag('peer.service', 'test-service')
          expect(span.get_tag('peer.service')).to eq(span.service)
          expect(span.service).not_to eq(Datadog.configuration.service)
          expect(described_class.send(:set_peer_service?, span)).to be false
        end
      end
    end

    context 'when span is not outbound' do
      context 'when span.kind is server' do
        it 'returns false' do
          span.set_tag('span.kind', 'server')
          expect(described_class.send(:set_peer_service?, span)).to be false
        end
      end

      context 'when span.kind is consumer' do
        it 'returns false' do
          span.set_tag('span.kind', 'consumer')
          expect(described_class.send(:set_peer_service?, span)).to be false
        end
      end
    end

    context 'when v1 is not set' do
      it 'returns false' do
        span.set_tag('span.kind', 'client')
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.send(:set_peer_service?, span)).to be false
        end
      end
    end

    context 'when peer service is not set and span is outbound and v1 is set' do
      it 'returns true' do
        span.set_tag('span.kind', 'client')
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.send(:set_peer_service?, span)).to be true
        end
      end
    end
  end

  describe '#set_peer_service_from_source' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceLogicSpan', parent_id: 0) }
    context 'AWS Span' do
      it 'returns {AWS_PRECURSOR} as peer.service and source' do
        span.set_tag('aws_service', 'test-service')
        span.set_tag('span.kind', 'client')
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          precursors = Array['statemachinename',
            'rulename',
            'bucketname',
            'tablename',
            'streamname',
            'topicname',
            'queuename']
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end
    end

    context 'DB Span' do
      it 'returns {DB_PRECURSOR} as peer.service and source' do
        span.set_tag('db.system', 'test-db')
        span.set_tag('span.kind', 'client')
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          precursors = Array['db.instance']
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end
    end

    context 'Messaging Span' do
      it 'returns {MSG_PRECURSOR} as peer.service and source' do
        span.set_tag('messaging.system', 'test-msg-system')
        span.set_tag('span.kind', 'producer')
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          precursors = Array[]
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end
    end

    context 'RPC Span' do
      it 'returns {RPC_PRECURSOR} as peer.service and source' do
        span.set_tag('rpc.system', 'test-rpc')
        span.set_tag('span.kind', 'client')
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          precursors = Array['rpc.service']
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end
    end

    context 'no precursor tags set' do
      context 'AWS Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('aws_service', 'test-service')
          span.set_tag('span.kind', 'client')
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

              span.clear_tag('peer.service')
              span.clear_tag('_dd.peer.service.source')
              span.clear_tag(precursor)
            end
          end
        end
      end

      context 'DB Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('db.system', 'test-db')
          span.set_tag('span.kind', 'client')
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

              span.clear_tag('peer.service')
              span.clear_tag('_dd.peer.service.source')
              span.clear_tag(precursor)
            end
          end
        end
      end

      context 'Messaging Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('messaging.system', 'test-msg-system')
          span.set_tag('span.kind', 'client')
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

              span.clear_tag('peer.service')
              span.clear_tag('_dd.peer.service.source')
              span.clear_tag(precursor)
            end
          end
        end
      end

      context 'RPC Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('rpc.system', 'test-rpc')
          span.set_tag('span.kind', 'client')
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service_from_source, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

              span.clear_tag('peer.service')
              span.clear_tag('_dd.peer.service.source')
              span.clear_tag(precursor)
            end
          end
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
