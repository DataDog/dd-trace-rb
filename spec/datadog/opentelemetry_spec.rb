require 'spec_helper'
require 'opentelemetry/sdk'
require 'datadog/opentelemetry'

RSpec.describe Datadog::OpenTelemetry do
  context 'with Datadog TraceProvider' do
    let(:otel_tracer) { OpenTelemetry.tracer_provider.tracer('otel-tracer') }
    let(:writer) { get_test_writer }
    let(:tracer) { Datadog::Tracing.send(:tracer) }
    let(:otel_root_parent) { OpenTelemetry::Trace::INVALID_SPAN_ID }

    let(:span_options) { {} }

    before do
      writer_ = writer
      Datadog.configure do |c|
        c.tracing.writer = writer_
        c.tracing.partial_flush.min_spans_threshold = 1 # Ensure tests flush spans quickly
        c.tracing.propagation_style = ['datadog'] # Ensure test has consistent propagation configuration
      end

      ::OpenTelemetry::SDK.configure do |c|
      end
    end

    after do
      ::OpenTelemetry.logger = nil
    end

    it 'returns the same tracer on successive calls' do
      expect(otel_tracer).to be(OpenTelemetry.tracer_provider.tracer('otel-tracer'))
    end

    shared_context 'parent and child spans' do
      let(:parent) { spans.find { |s| s.parent_id == 0 } }
      let(:child) { spans.find { |s| s != parent } }

      it { expect(spans).to have(2).items }

      it 'have child-parent relationship' do
        expect(parent).to be_root_span
        expect(child.parent_id).to eq(parent.id)
      end
    end

    describe '#in_span' do
      context 'without an active span' do
        subject(:in_span) { otel_tracer.in_span('test', **span_options) {} }

        it 'records a finished span' do
          in_span

          expect(span).to be_root_span
          expect(span.name).to eq('internal')
          expect(span.resource).to eq('test')
          expect(span.service).to eq(tracer.default_service)
        end

        context 'with attributes' do
          let(:span_options) { { attributes: attributes } }

          before do
            Datadog.configure do |c|
              c.tags = { 'global' => 'global_tag' }
            end

            in_span
          end

          [
            [1, 1],
            [false, 'false'],
            [true, 'true'],
            ['str', 'str'],
          ].each do |input, expected|
            context "with attribute value #{input}" do
              let(:attributes) { { 'tag' => input } }

              it "sets tag #{expected}" do
                expect(span.get_tag('tag')).to eq(expected)
              end

              it 'keeps the global trace tags' do
                expect(span.get_tag('global')).to eq('global_tag')
              end
            end
          end

          [
            [[1], { 'key.0' => 1 }],
            [[true, false], { 'key.0' => 'true', 'key.1' => 'false' }],
          ].each do |input, expected|
            context "with an array attribute value #{input}" do
              let(:attributes) { { 'key' => input } }

              it "sets tags #{expected}" do
                expect(span.tags).to include(expected)
              end
            end
          end

          context 'with a numeric attribute' do
            let(:attributes) { { 'tag' => 1 } }

            it 'sets it as a metric' do
              expect(span.get_metric('tag')).to eq(1)
            end
          end

          context 'with reserved attributes' do
            let(:attributes) { { attribute_name => attribute_value } }

            context 'for operation.name' do
              let(:attribute_name) { 'operation.name' }
              let(:attribute_value) { 'Override.name' }

              it 'overrides the respective Datadog span name' do
                expect(span.name).to eq(attribute_value)
              end
            end

            context 'for resource.name' do
              let(:attribute_name) { 'resource.name' }
              let(:attribute_value) { 'new.name' }

              it 'overrides the respective Datadog span resource' do
                expect(span.resource).to eq(attribute_value)
              end
            end

            context 'for service.name' do
              let(:attribute_name) { 'service.name' }
              let(:attribute_value) { 'new.service.name' }

              it 'overrides the respective Datadog span service' do
                expect(span.service).to eq(attribute_value)
              end
            end

            context 'for span.type' do
              let(:attribute_name) { 'span.type' }
              let(:attribute_value) { 'new.span.type' }

              it 'overrides the respective Datadog span type' do
                expect(span.type).to eq(attribute_value)
              end
            end

            context 'for analytics.event' do
              let(:attribute_name) { 'analytics.event' }

              context 'true' do
                let(:attribute_value) { 'true' }

                it 'overrides the respective Datadog span tag' do
                  expect(span.get_metric('_dd1.sr.eausr')).to eq(1)
                end
              end

              context 'false' do
                let(:attribute_value) { 'false' }

                it 'overrides the respective Datadog span tag' do
                  expect(span.get_metric('_dd1.sr.eausr')).to eq(0)
                end
              end
            end

            context 'for http.response.status_code' do
              let(:attribute_name) { 'http.response.status_code' }
              let(:attribute_value) { '200' }

              it 'overrides the respective Datadog span name' do
                expect(span.get_tag('http.status_code')).to eq('200')
              end
            end
          end

          context 'for OpenTelemetry semantic convention' do
            [
              [:internal, {}, 'internal'],
              [
                :producer,
                { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' },
                'kafka.receive'
              ],
              [:producer, {}, 'producer'],
              [
                :consumer,
                { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' },
                'kafka.receive'
              ],
              [:consumer, {}, 'consumer'],
              [:client, { 'http.request.method' => 'GET' }, 'http.client.request'],
              [:client, { 'db.system' => 'Redis' }, 'redis.query'],
              [:client, { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' }, 'kafka.receive'],
              [:client, { 'rpc.system' => 'aws-api', 'rpc.service' => 'S3' }, 'aws.s3.request'],
              [:client, { 'rpc.system' => 'aws-api' }, 'aws.client.request'],
              [:client, { 'rpc.system' => 'GRPC' }, 'grpc.client.request'],
              [
                :client,
                { 'faas.invoked_provider' => 'aws', 'faas.invoked_name' => 'My-Function' },
                'aws.my-function.invoke'
              ],
              [:client, { 'network.protocol.name' => 'Amqp' }, 'amqp.client.request'],
              [:client, {}, 'client.request'],
              [:server, { 'http.request.method' => 'GET' }, 'http.server.request'],
              [:server, { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' }, 'kafka.receive'],
              [:server, { 'rpc.system' => 'GRPC' }, 'grpc.server.request'],
              [:server, { 'faas.trigger' => 'Datasource' }, 'datasource.invoke'],
              [:server, { 'graphql.operation.type' => 'query' }, 'graphql.server.request'],
              [:server, { 'network.protocol.name' => 'Amqp' }, 'amqp.server.request'],
              [:server, {}, 'server.request'],
            ].each do |kind, attributes, expected_operation_name|
              context "for kind #{kind} and attributes #{attributes}" do
                let(:span_options) { { kind: kind, attributes: attributes } }
                it { expect(span.name).to eq(expected_operation_name) }
              end
            end

            context 'with operation name override' do
              let(:span_options) { { kind: :client, attributes: { 'operation.name' => 'override' } } }
              it 'takes precedence over semantic convention' do
                expect(span.name).to eq('override')
              end
            end
          end
        end

        context 'with start_timestamp' do
          let(:span_options) { { start_timestamp: start_timestamp } }
          let(:start_timestamp) { Time.utc(2023) }
          it do
            in_span
            expect(span.start_time).to eq(start_timestamp)
          end
        end
      end

      context 'with an active span' do
        subject!(:in_span) do
          otel_tracer.in_span('otel-parent') do
            otel_tracer.in_span('otel-child') {}
          end
        end

        include_context 'parent and child spans'

        it 'sets parent to active span' do
          expect(parent.resource).to eq('otel-parent')
          expect(child.resource).to eq('otel-child')

          expect(spans).to have(2).items
        end
      end

      context 'with an active Datadog span' do
        subject!(:in_span) do
          tracer.trace('datadog-parent') do
            otel_tracer.in_span('otel-child') {}
          end
        end

        include_context 'parent and child spans'

        it 'sets parent to active span' do
          expect(parent.name).to eq('datadog-parent')
          expect(child.resource).to eq('otel-child')
        end
      end

      context 'with a Datadog child span' do
        subject!(:in_span) do
          otel_tracer.in_span('otel-parent') do
            tracer.trace('datadog-child') {}
          end
        end

        include_context 'parent and child spans'

        it 'attaches Datadog span as a child' do
          expect(parent.resource).to eq('otel-parent')
          expect(child.name).to eq('datadog-child')
        end
      end
    end

    describe '#start_span' do
      subject(:start_span) { otel_tracer.start_span('start-span', **options) }
      let(:options) { {} }

      it 'creates an unfinished span' do
        expect(start_span.parent_span_id).to eq(otel_root_parent)
        expect(start_span.name).to eq('start-span')
        expect(spans).to be_empty
      end

      it 'records span on finish' do
        start_span.finish
        expect(span.resource).to eq('start-span')
      end

      context 'with existing active span' do
        let!(:existing_span) { otel_tracer.start_span('existing-active-span') }

        context 'with parent and child spans' do
          include_context 'parent and child spans'

          before do
            start_span.finish
            existing_span.finish
          end

          it 'sets parent to active span' do
            expect(parent.resource).to eq('existing-active-span')
            expect(child.resource).to eq('start-span')
          end
        end

        context 'that has already finished' do
          let(:options) { { with_parent: ::OpenTelemetry::Trace.context_with_span(existing_span) } }
          let(:parent) { spans.find { |s| s.parent_id == 0 } }
          let(:child) { spans.find { |s| s != parent } }

          it 'correctly parents and flushed the child span' do
            existing_span.finish
            start_span.finish

            expect(parent).to be_root_span
            expect(child.parent_id).to eq(parent.id)
          end

          it 'the underlying datadog spans has the same ids as the otel spans' do
            existing_span.finish
            start_span.finish
            # Verify Span IDs are the same
            expect(existing_span.context.hex_span_id.to_i(16)).to eq(parent.id)
            expect(start_span.context.hex_span_id.to_i(16)).to eq(child.id)
            # Verify Trace IDs are the same
            expect(existing_span.context.hex_trace_id.to_i(16)).to eq(parent.trace_id)
            expect(start_span.context.hex_trace_id.to_i(16)).to eq(child.trace_id)
          end
        end
      end

      context 'and #finish with a timestamp' do
        let(:timestamp) { Time.utc(2023) }

        it 'sets the matching timestamp' do
          start_span.finish(end_timestamp: timestamp)

          expect(span.end_time).to eq(timestamp)
        end
      end

      context 'with span_links' do
        let(:sc1) do
          OpenTelemetry::Trace::SpanContext.new(
            trace_id: ['000000000000006d5b953ca4d9c834ab'].pack('H*'),
            span_id: ['0000000fcec36d3f'].pack('H*')
          )
        end
        let(:sc2) do
          OpenTelemetry::Trace::SpanContext.new(
            trace_id: ['0000000000000000000000000012d666'].pack('H*'),
            span_id: ['000000000000000a'].pack('H*'),
            trace_flags: OpenTelemetry::Trace::TraceFlags::SAMPLED,
            tracestate: OpenTelemetry::Trace::Tracestate.from_string('otel=blahxd')
          )
        end
        let(:links) do
          [
            OpenTelemetry::Trace::Link.new(sc1, { 'key' => 'val', '1' => true }),
            OpenTelemetry::Trace::Link.new(sc2, { 'key2' => true, 'list' => [1, 2] }),
          ]
        end
        let(:options) { { links: links } }

        it 'sets span links' do
          start_span.finish
          expect(span.links.size).to eq(2)

          expect(span.links[0].trace_id).to eq(2017294351542048535723)
          expect(span.links[0].span_id).to eq(67893423423)
          expect(span.links[0].trace_flags).to eq(0)
          expect(span.links[0].trace_state).to eq('')
          expect(span.links[0].attributes).to eq({ 'key' => 'val', '1' => true })

          expect(span.links[1].trace_id).to eq(1234534)
          expect(span.links[1].span_id).to eq(10)
          expect(span.links[1].trace_flags).to eq(1)
          expect(span.links[1].trace_state).to eq('otel=blahxd')
          expect(span.links[1].attributes).to eq({ 'key2' => true, 'list' => [1, 2] })
        end
      end
    end

    describe '#start_root_span' do
      subject(:start_root_span) { otel_tracer.start_root_span('start-root-span') }

      before { otel_tracer.start_span('existing-active-span') }

      it 'creates an unfinished span' do
        expect(start_root_span.parent_span_id).to eq(otel_root_parent)
        expect(start_root_span.name).to eq('start-root-span')

        expect(spans).to be_empty
      end

      it 'records span independently from other existing spans' do
        start_root_span.finish
        expect(span.resource).to eq('start-root-span')
      end
    end

    shared_context 'Span#set_attribute' do
      subject(:set_attribute) { start_span.public_send(setter, attribute_name, attribute_value) }
      let(:start_span) { otel_tracer.start_span('start-span', **span_options) }
      let(:active_span) { Datadog::Tracing.active_span }
      let(:attribute_name) { 'key' }
      let(:attribute_value) { 'value' }

      it 'sets Datadog tag' do
        start_span

        expect { set_attribute }.to change { active_span.get_tag('key') }.from(nil).to('value')

        start_span.finish

        expect(span.get_tag('key')).to eq('value')
      end

      [
        [1, 1],
        [false, 'false'],
        [true, 'true'],
        ['str', 'str'],
      ].each do |input, expected|
        context "with attribute value #{input}" do
          let(:attribute_name) { 'tag' }
          let(:attribute_value) { input }

          it "sets tag #{expected}" do
            set_attribute
            start_span.finish

            expect(span.get_tag('tag')).to eq(expected)
          end
        end
      end

      [
        [[1], { 'key.0' => 1 }],
        [[true, false], { 'key.0' => 'true', 'key.1' => 'false' }],
      ].each do |input, expected|
        context "with an array attribute value #{input}" do
          let(:attribute_name) { 'key' }
          let(:attribute_value) { input }

          it "sets tags #{expected}" do
            set_attribute
            start_span.finish

            expect(span.tags).to include(expected)
          end
        end
      end

      context 'with reserved attributes' do
        before do
          set_attribute
          start_span.finish
        end

        context 'for operation.name' do
          let(:attribute_name) { 'operation.name' }
          let(:attribute_value) { 'Override.name' }

          it 'overrides the respective Datadog span name' do
            expect(span.name).to eq(attribute_value)
          end
        end

        context 'for resource.name' do
          let(:attribute_name) { 'resource.name' }
          let(:attribute_value) { 'new.name' }

          it 'overrides the respective Datadog span resource' do
            expect(span.resource).to eq(attribute_value)
          end
        end

        context 'for service.name' do
          let(:attribute_name) { 'service.name' }
          let(:attribute_value) { 'new.service.name' }

          it 'overrides the respective Datadog span service' do
            expect(span.service).to eq(attribute_value)
          end
        end

        context 'for span.type' do
          let(:attribute_name) { 'span.type' }
          let(:attribute_value) { 'new.span.type' }

          it 'overrides the respective Datadog span type' do
            expect(span.type).to eq(attribute_value)
          end
        end

        context 'for analytics.event' do
          let(:attribute_name) { 'analytics.event' }

          context 'true' do
            let(:attribute_value) { 'true' }

            it 'overrides the respective Datadog span tag' do
              expect(span.get_metric('_dd1.sr.eausr')).to eq(1)
            end
          end

          context 'false' do
            let(:attribute_value) { 'false' }

            it 'overrides the respective Datadog span tag' do
              expect(span.get_metric('_dd1.sr.eausr')).to eq(0)
            end
          end
        end

        context 'for http.response.status_code' do
          let(:attribute_name) { 'http.response.status_code' }
          let(:attribute_value) { '200' }

          it 'overrides the respective Datadog span name' do
            expect(span.get_tag('http.status_code')).to eq('200')
          end
        end

        context 'for OpenTelemetry semantic convention' do
          [
            [:internal, {}, 'internal'],
            [
              :producer,
              { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' },
              'kafka.receive'
            ],
            [:producer, {}, 'producer'],
            [
              :consumer,
              { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' },
              'kafka.receive'
            ],
            [:consumer, {}, 'consumer'],
            [:client, { 'http.request.method' => 'GET' }, 'http.client.request'],
            [:client, { 'db.system' => 'Redis' }, 'redis.query'],
            [:client, { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' }, 'kafka.receive'],
            [:client, { 'rpc.system' => 'aws-api', 'rpc.service' => 'S3' }, 'aws.s3.request'],
            [:client, { 'rpc.system' => 'aws-api' }, 'aws.client.request'],
            [:client, { 'rpc.system' => 'GRPC' }, 'grpc.client.request'],
            [
              :client,
              { 'faas.invoked_provider' => 'aws', 'faas.invoked_name' => 'My-Function' },
              'aws.my-function.invoke'
            ],
            [:client, { 'network.protocol.name' => 'Amqp' }, 'amqp.client.request'],
            [:client, {}, 'client.request'],
            [:server, { 'http.request.method' => 'GET' }, 'http.server.request'],
            [:server, { 'messaging.system' => 'Kafka', 'messaging.operation' => 'Receive' }, 'kafka.receive'],
            [:server, { 'rpc.system' => 'GRPC' }, 'grpc.server.request'],
            [:server, { 'faas.trigger' => 'Datasource' }, 'datasource.invoke'],
            [:server, { 'graphql.operation.type' => 'query' }, 'graphql.server.request'],
            [:server, { 'network.protocol.name' => 'Amqp' }, 'amqp.server.request'],
            [:server, {}, 'server.request'],
          ].each do |kind, attributes, expected_operation_name|
            context "for kind #{kind} and attributes #{attributes}" do
              subject(:set_attribute) do
                attributes.each do |name, value|
                  start_span.public_send(setter, name, value)
                end
              end

              let(:span_options) { { kind: kind } }

              it { expect(span.name).to eq(expected_operation_name) }
            end
          end

          context 'with operation name override' do
            let(:span_options) { { kind: :client } }
            let(:attribute_name) { 'operation.name' }
            let(:attribute_value) { 'override' }

            it 'takes precedence over semantic convention' do
              expect(span.name).to eq('override')
            end
          end
        end
      end
    end

    describe '#set_attribute' do
      include_context 'Span#set_attribute'
      let(:setter) { :set_attribute }
    end

    describe '#record_exception' do
      subject! do
        start_span
        start_span.record_exception(StandardError.new('Error'), attributes: attributes)
        start_span.finish
      end

      let(:start_span) { otel_tracer.start_span('start-span', **span_options) }
      let(:active_span) { Datadog::Tracing.active_span }

      Array([nil, {}]).each do |attrs|
        context "attributes is #{attrs.inspect}" do
          let(:attributes) { attrs }

          it 'sets records an exception event and sets span error tags using the Exception object' do
            expect(span.events.count).to eq(1)
            expect(span.events[0].name).to eq('exception')
            expect(span.events[0].time_unix_nano / 1e9).to be_within(1).of(Time.now.to_f)

            expect(span.events[0].attributes.keys).to match_array(
              ['exception.message', 'exception.type',
               'exception.stacktrace']
            )
            expect(span.events[0].attributes['exception.message']).to eq('Error')
            expect(span.events[0].attributes['exception.type']).to eq('StandardError')
            expect(span.events[0].attributes['exception.stacktrace']).to include(
              ":in `full_message': Error (StandardError)"
            )
            expect(span).to_not have_error
            expect(span).to have_error_message('Error')
            expect(span).to have_error_stack(include(":in `full_message': Error (StandardError)"))
            expect(span).to have_error_type('StandardError')
          end
        end
      end

      context 'with attributes containing nil values' do
        let(:attributes) { { 'exception.stacktrace' => nil, 'exception.type' => nil, 'exception.message' => nil } }

        it 'sets records an exception event and sets span error tags using the Exception object' do
          expect(span.events.count).to eq(1)
          expect(span.events[0].name).to eq('exception')
          expect(span.events[0].attributes).to eq({})
          expect(span).to_not have_error
          expect(span).to have_error_message('Error')
          expect(span).to have_error_stack(include(":in `full_message': Error (StandardError)"))
          expect(span).to have_error_type('StandardError')
        end
      end

      context 'with attributes containing empty values' do
        let(:attributes) { { 'exception.stacktrace' => '', 'exception.type' => '', 'exception.message' => '' } }

        it 'sets records an exception event and does NOT set span error tags' do
          expect(span.events.count).to eq(1)
          expect(span.events[0].name).to eq('exception')
          expect(span.events[0].attributes).to eq(attributes)
          expect(span).to_not have_error
          expect(span).to_not have_error_message
          expect(span).to_not have_error_stack
          expect(span).to_not have_error_type
        end
      end

      context 'with attributes containing exception stacktrace, type and message' do
        let(:attributes) do
          { 'exception.stacktrace' => 'funny_stack', 'exception.type' => 'CustomError', 'exception.message' => 'NewError',
            'candy' => true }
        end

        it 'sets records an exception event and sets span error tags using the attributes hash' do
          expect(span.events.count).to eq(1)
          expect(span.events[0].name).to eq('exception')
          expect(span.events[0].time_unix_nano / 1e9).to be_within(1).of(Time.now.to_f)
          expect(span.events[0].attributes).to eq(attributes)
          expect(span).to_not have_error
          expect(span).to have_error_message('NewError')
          expect(span).to have_error_stack('funny_stack')
          expect(span).to have_error_type('CustomError')
        end
      end
    end

    describe '#[]=' do
      include_context 'Span#set_attribute'
      let(:setter) { :[]= }
    end

    describe '#add_attributes' do
      subject(:add_attributes) { start_span.add_attributes({ 'k1' => 'v1', 'k2' => 'v2' }) }
      let(:start_span) { otel_tracer.start_span('start-span', **span_options) }
      let(:active_span) { Datadog::Tracing.active_span }

      it 'sets Datadog tag' do
        start_span

        expect { add_attributes }.to change { active_span.get_tag('k1') }.from(nil).to('v1')

        start_span.finish

        expect(span.get_tag('k1')).to eq('v1')
        expect(span.get_tag('k2')).to eq('v2')
      end
    end

    describe '#add_event' do
      subject! do
        start_span
        start_span.add_event('Exception was raised!', attributes: attributes, timestamp: timestamp)
        start_span.finish
      end

      let(:start_span) { otel_tracer.start_span('start-span', **span_options) }
      let(:active_span) { Datadog::Tracing.active_span }

      context 'with name, attributes and timestamp' do
        let(:attributes) { { 'raised' => false, 'handler' => 'default', 'count' => 1 } }
        let(:timestamp) { 17206369349 }

        it 'adds one event to the span' do
          expect(span.events.count).to eq(1)
          expect(span.events[0].name).to eq('Exception was raised!')
          expect(span.events[0].time_unix_nano).to eq(17206369349000000000)
          expect(span.events[0].attributes).to eq(attributes)
        end
      end

      context 'without a timestamp or attributes' do
        let(:attributes) { {} }
        let(:timestamp) { nil }

        it 'adds one event with timestamp set to the current time and attributes set to an empty hash' do
          expect(span.events.count).to eq(1)
          expect(span.events[0].name).to eq('Exception was raised!')
          expect(span.events[0].time_unix_nano / 1e9).to be_within(1).of(Time.now.to_f)
          expect(span.events[0].attributes).to eq({})
        end
      end
    end

    describe '#status=' do
      subject! do
        start_span
        set_status
        start_span.finish
      end

      let(:set_status) { start_span.status = status }
      let(:start_span) { otel_tracer.start_span('start-span') }
      let(:active_span) { Datadog::Tracing.active_span }

      context 'with ok' do
        let(:status) { OpenTelemetry::Trace::Status.ok }

        it 'does not change status' do
          expect(span).to_not have_error
        end
      end

      context 'with error' do
        let(:status) { OpenTelemetry::Trace::Status.error('my-error') }

        it 'changes to error with a message' do
          expect(span).to have_error
          expect(span).to have_error_message('my-error')
          expect(span).to have_error_message(start_span.status.description)
        end

        context 'then ok' do
          subject! do
            start_span

            set_status # Sets to error
            start_span.status = OpenTelemetry::Trace::Status.ok

            start_span.finish
          end

          it 'cannot revert back from an error' do
            expect(span).to have_error
            expect(span).to have_error_message('my-error')
          end
        end

        context 'and another error' do
          subject! do
            start_span

            set_status # Sets to error
            start_span.status = OpenTelemetry::Trace::Status.error('another-error')

            start_span.finish
          end

          it 'overrides the error message' do
            expect(span).to have_error
            expect(span).to have_error_message('another-error')
            expect(span).to have_error_message(start_span.status.description)
          end
        end
      end

      context 'with unset' do
        let(:status) { OpenTelemetry::Trace::Status.unset }

        it 'does not change status' do
          expect(span).to_not have_error
        end
      end
    end

    context 'OpenTelemetry.logger' do
      it 'is the Datadog logger' do
        expect(::OpenTelemetry.logger).to eq(::Datadog.logger)
      end
    end

    context 'OpenTelemetry.propagation' do
      describe '#inject' do
        subject(:inject) do
          ::OpenTelemetry.propagation.inject(carrier)
        end
        let(:carrier) { {} }
        let(:trace_id) { Datadog::Tracing.active_trace.id }
        def headers
          {
            'x-datadog-parent-id' => Datadog::Tracing.active_span.id.to_s,
            'x-datadog-sampling-priority' => '1',
            'x-datadog-tags' => '_dd.p.dm=-0' + (
              trace_id < 2**64 ? '' : ",_dd.p.tid=#{high_order_hex_trace_id(Datadog::Tracing.active_trace.id)}"
            ),
            'x-datadog-trace-id' => low_order_trace_id(Datadog::Tracing.active_trace.id).to_s,
          }
        end

        context 'with an active span' do
          before { otel_tracer.start_span('existing-active-span') }

          it 'injects Datadog headers' do
            inject
            expect(carrier).to eq(headers)
          end
        end

        context 'with an active Datadog span' do
          before { tracer.trace('existing-active-span') }

          it 'injects Datadog headers' do
            inject
            expect(carrier).to eq(headers)
          end
        end
      end

      describe '#extract' do
        subject(:extract) { ::OpenTelemetry.propagation.extract(carrier) }
        let(:carrier) { {} }

        context 'with Datadog headers' do
          let(:carrier) do
            {
              'x-datadog-parent-id' => '123',
              'x-datadog-sampling-priority' => '1',
              'x-datadog-tags' => '_dd.p.dm=-0',
              'x-datadog-trace-id' => '456',
            }
          end

          before do
            # Ensure background Writer worker doesn't wait, making tests faster.
            stub_const('Datadog::Tracing::Workers::AsyncTransport::DEFAULT_FLUSH_INTERVAL', 0)
          end

          it 'sucessive calls to #with_current leave tracer in a consistent state' do
            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            try_wait_until { spans[0]['_sampling_priority_v1'] } # Wait for TraceFormatter to modify the trace

            span = spans[0]

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0'), Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)

            span = spans[1]

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0'), Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)
          end

          it 'extracts into the active context' do
            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            try_wait_until { span['_sampling_priority_v1'] } # Wait for TraceFormatter to modify the trace

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0') # , Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)
          end

          it 'extracts into the active Datadog context' do
            OpenTelemetry::Context.with_current(extract) do
              tracer.trace('datadog') {}
            end

            try_wait_until { span['_sampling_priority_v1'] } # Wait for TraceFormatter to modify the trace

            expect(span.parent_id).to eq(123)
            expect(span.trace_id).to eq(456)
            expect(span['_dd.p.dm']).to eq('-0'), Datadog::Tracing.active_trace.inspect
            expect(span['_sampling_priority_v1']).to eq(1)
          end
        end

        context 'with TraceContext headers' do
          let(:carrier) do
            {
              'traceparent' => '00-11111111111111111111111111111111-2222222222222222-01'
            }
          end

          before do
            Datadog.configure do |c|
              c.tracing.propagation_style_extract = ['datadog', 'tracecontext']
            end
          end

          it 'extracts into the active context' do
            OpenTelemetry::Context.with_current(extract) do
              otel_tracer.in_span('otel') {}
            end

            expect(span.trace_id).to eq(0x11111111111111111111111111111111)
            expect(span.parent_id).to eq(0x2222222222222222)
          end
        end
      end
    end
  end
end
