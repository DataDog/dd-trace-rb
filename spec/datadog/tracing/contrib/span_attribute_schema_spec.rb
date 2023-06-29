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

  describe '#active_version' do
    context 'when v0 set' do
      it 'equals v0' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.send(:active_version)).to eq(described_class::VersionZero)
        end
      end
    end

    context 'when v1 is set' do
      it 'equals v1' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.send(:active_version)).to eq(described_class::VersionOne)
        end
      end
    end

    context 'when no schema is set' do
      it 'equals v0' do
        expect(described_class.send(:active_version)).to eq(described_class::VersionZero)
      end
    end
  end

  describe '#fetch_service_name' do
    context 'for v0' do
      context 'when integration service is set' do
        it 'returns the integration specific service name' do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0', DD_INTEGRATION_SERVICE: 'integration-service-name' do
            expect(
              described_class
                .fetch_service_name('DD_INTEGRATION_SERVICE',
                  'default-integration-service-name')
            ).to eq('integration-service-name')
          end
        end
      end

      context 'when DD_SERVICE is set' do
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

      context 'when DD_SERVICE is not set' do
        it 'returns default integration service name' do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
            expect(
              described_class
                .fetch_service_name('DD_INTEGRATION_SERVICE',
                  'default-integration-service-name')
            ).to eq('default-integration-service-name')
          end
        end
      end
    end

    context 'for v1' do
      context 'when integration service is set' do
        it 'returns the integration specific service name' do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1', DD_INTEGRATION_SERVICE: 'integration-service-name' do
            expect(
              described_class
                .fetch_service_name('DD_INTEGRATION_SERVICE',
                  'default-integration-service-name')
            ).to eq('integration-service-name')
          end
        end
      end

      context 'when DD_SERVICE is set' do
        it 'returns default integration service name' do
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
        it 'returns default integration service name' do
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
  end

  describe '#set_peer_service!' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceLogicSpan', parent_id: 0) }
    context 'for v0' do
      it 'returns {span.service} and peer.service as source' do
        span.service = 'test-peer.service'
        expect(described_class.send(:set_peer_service!, span, [])).to be false
        expect(span.get_tag('peer.service')).to eq('test-peer.service')
        expect(span.get_tag('_dd.peer.service.source')).to eq nil
      end
    end

    context 'for v1' do
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

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

                expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

                expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

                expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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

                expect(described_class.send(:set_peer_service!, span, precursors)).to be true
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
  end

  # Add test return true if env var is true
  describe 'test VersionOne only sets peer.service when correct' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceSpan', parent_id: 0) }
    context 'for v1' do
      context 'when peer.service exists' do
        it 'returns false' do
          span.set_tag('peer.service', 'test')
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            expect(described_class.send(:set_peer_service!, span, [])).to be false
          end
        end
      end

      context 'when span is not outbound' do
        context 'when span.kind is server' do
          it 'returns false' do
            span.set_tag('span.kind', 'server')
            with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
              expect(described_class.send(:set_peer_service!, span, [])).to be false
            end
          end
        end

        context 'when span.kind is consumer' do
          it 'returns false' do
            span.set_tag('span.kind', 'consumer')
            with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
              expect(described_class.send(:set_peer_service!, span, [])).to be false
            end
          end
        end
      end

      context 'when peer service is not set and span is outbound and v1 is set' do
        it 'returns true' do
          span.set_tag('span.kind', 'client')
          span.set_tag('out.host', 'test')
          span.set_tag('rpc.system', 'test-rpc')

          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
            expect(described_class.send(:set_peer_service!, span, ['out.host'])).to be true
          end
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
