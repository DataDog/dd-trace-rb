require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::Tracer do
    include_context 'OpenTracing helpers'

    subject(:tracer) { described_class.new(writer: FauxWriter.new) }
    let(:datadog_tracer) { tracer.datadog_tracer }
    let(:datadog_spans) { datadog_tracer.writer.spans(:keep) }

    def current_trace_for(object)
      case object
      when Datadog::OpenTracer::Span
        object.context.datadog_context.instance_variable_get(:@trace)
      when Datadog::OpenTracer::SpanContext
        object.datadog_context.instance_variable_get(:@trace)
      when Datadog::OpenTracer::Scope
        object.span.context.datadog_context.instance_variable_get(:@trace)
      end
    end

    describe '#start_span' do
      context 'for a single span' do
        context 'without a block' do
          let(:span) { tracer.start_span(span_name, **options) }
          let(:span_name) { 'operation.foo' }
          let(:options) { {} }
          before(:each) { span.finish }

          let(:datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(1).items }
          it { expect(datadog_span.name).to eq(span_name) }
          it { expect(datadog_span.finished?).to be(true) }

          context 'when given start_time' do
            let(:options) { { start_time: start_time } }
            let(:start_time) { Time.new(2000, 1, 1) }
            it { expect(datadog_span.start_time).to be(start_time) }
          end

          context 'when given tags' do
            let(:options) { { tags: tags } }
            let(:tags) { { 'operation.type' => 'validate', 'account_id' => 1 } }
            it { tags.each { |k, v| expect(datadog_span.get_tag(k)).to eq(v.is_a?(Numeric) ? v.to_f : v) } }
          end
        end
      end

      context 'for a nested span' do
        context 'when there is no active scope' do
          before(:each) do
            tracer.start_span('operation.outer').tap do |_outer_span|
              tracer.start_span('operation.inner').tap do |inner_span|
                # Assert Datadog context integrity
                # 1 item because they each should get their own context.
                expect(current_trace_for(inner_span)).to have(1).items
                expect(current_trace_for(inner_span)).to include(inner_span.datadog_span)
              end.finish
            end.finish
          end

          let(:outer_datadog_span) { datadog_spans.last }
          let(:inner_datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(2).items }
          it { expect(outer_datadog_span.name).to eq('operation.outer') }
          it { expect(outer_datadog_span.parent_id).to eq(0) }
          it { expect(outer_datadog_span.finished?).to be true }
          it { expect(inner_datadog_span.name).to eq('operation.inner') }
          it { expect(inner_datadog_span.parent_id).to eq(0) }
          it { expect(inner_datadog_span.finished?).to be true }
        end

        context 'when there is an active scope' do
          context 'which is used' do
            before(:each) do
              tracer.start_active_span('operation.parent') do |parent_scope|
                tracer.start_span('operation.child').tap do |span|
                  # Assert Datadog context integrity
                  expect(current_trace_for(span)).to have(2).items
                  expect(current_trace_for(span)).to include(parent_scope.span.datadog_span, span.datadog_span)
                end.finish
              end
            end

            let(:parent_datadog_span) { datadog_spans.last }
            let(:child_datadog_span) { datadog_spans.first }

            it { expect(datadog_spans).to have(2).items }
            it { expect(parent_datadog_span.name).to eq('operation.parent') }
            it { expect(parent_datadog_span.parent_id).to eq(0) }
            it { expect(parent_datadog_span.finished?).to be true }
            it { expect(child_datadog_span.name).to eq('operation.child') }
            it { expect(child_datadog_span.parent_id).to eq(parent_datadog_span.span_id) }
            it { expect(child_datadog_span.finished?).to be true }
          end

          context 'which is ignored' do
            before(:each) do
              tracer.start_active_span('operation.parent') do |_scope|
                tracer.start_span('operation.child', ignore_active_scope: true).tap do |span|
                  # Assert Datadog context integrity
                  expect(current_trace_for(span)).to have(1).items
                  expect(current_trace_for(span)).to include(span.datadog_span)
                end.finish
              end
            end

            let(:parent_datadog_span) { datadog_spans.last }
            let(:child_datadog_span) { datadog_spans.first }

            it { expect(datadog_spans).to have(2).items }
            it { expect(parent_datadog_span.name).to eq('operation.parent') }
            it { expect(parent_datadog_span.parent_id).to eq(0) }
            it { expect(parent_datadog_span.finished?).to be true }
            it { expect(child_datadog_span.name).to eq('operation.child') }
            it { expect(child_datadog_span.parent_id).to eq(0) }
            it { expect(child_datadog_span.finished?).to be true }
          end
        end

        context 'manually associated with child_of' do
          before(:each) do
            tracer.start_span('operation.parent').tap do |parent_span|
              tracer.start_active_span('operation.fake_parent') do
                tracer.start_span('operation.child', child_of: parent_span).tap do |span|
                  # Assert Datadog context integrity
                  expect(current_trace_for(span)).to have(2).items
                  expect(current_trace_for(span)).to include(parent_span.datadog_span, span.datadog_span)
                end.finish
              end
            end.finish
          end

          let(:parent_datadog_span) { datadog_spans[2] }
          let(:fake_parent_datadog_span) { datadog_spans[1] }
          let(:child_datadog_span) { datadog_spans[0] }

          it { expect(datadog_spans).to have(3).items }
          it { expect(parent_datadog_span.name).to eq('operation.parent') }
          it { expect(parent_datadog_span.parent_id).to eq(0) }
          it { expect(parent_datadog_span.finished?).to be true }
          it { expect(child_datadog_span.name).to eq('operation.child') }
          it { expect(child_datadog_span.parent_id).to eq(parent_datadog_span.span_id) }
          it { expect(child_datadog_span.finished?).to be true }
        end
      end

      context 'for sibling span' do
        before(:each) do
          tracer.start_span('operation.older_sibling').finish
          tracer.start_span('operation.younger_sibling').tap do |span|
            # Assert Datadog context integrity
            expect(current_trace_for(span)).to have(1).items
            expect(current_trace_for(span)).to include(span.datadog_span)
          end.finish
        end

        let(:older_datadog_span) { datadog_spans.first }
        let(:younger_datadog_span) { datadog_spans.last }

        it { expect(datadog_spans).to have(2).items }
        it { expect(older_datadog_span.name).to eq('operation.older_sibling') }
        it { expect(older_datadog_span.parent_id).to eq(0) }
        it { expect(older_datadog_span.finished?).to be true }
        it { expect(younger_datadog_span.name).to eq('operation.younger_sibling') }
        it { expect(younger_datadog_span.parent_id).to eq(0) }
        it { expect(younger_datadog_span.finished?).to be true }
      end
    end

    describe '#start_active_span' do
      let(:span_name) { 'operation.foo' }
      let(:options) { {} }

      context 'for a single span' do
        context 'without a block' do
          before(:each) { tracer.start_active_span(span_name, **options).close }

          let(:datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(1).items }
          it { expect(datadog_span.name).to eq(span_name) }
          it { expect(datadog_span.finished?).to be(true) }

          context 'when given start_time' do
            let(:options) { { start_time: start_time } }
            let(:start_time) { Time.new(2000, 1, 1) }
            it { expect(datadog_span.start_time).to be(start_time) }
          end

          context 'when given tags' do
            let(:options) { { tags: tags } }
            let(:tags) { { 'operation.type' => 'validate', 'account_id' => 1 } }
            it { tags.each { |k, v| expect(datadog_span.get_tag(k)).to eq(v.is_a?(Numeric) ? v.to_f : v) } }
          end
        end

        context 'with a block' do
          before(:each) { tracer.start_active_span(span_name, **options) { |scope| @scope = scope } }

          it do
            expect { |b| tracer.start_active_span(span_name, &b) }.to yield_with_args(
              a_kind_of(Datadog::OpenTracer::Scope)
            )
          end

          let(:datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(1).items }
          it { expect(datadog_span.name).to eq(span_name) }
          it { expect(datadog_span.finished?).to be(true) }

          context 'when given finish_on_close' do
            context 'as true' do
              let(:options) { { finish_on_close: true } }
              it { expect(datadog_span.finished?).to be(true) }
            end

            context 'as false' do
              let(:options) { { finish_on_close: false } }
              let(:datadog_span) { @scope.span.datadog_span }
              it { expect(datadog_span.finished?).to be(false) }
            end
          end
        end

        context 'preceded by a Datadog span' do
          let(:parent_span_name) { 'operation.bar' }
          let(:options) { { finish_on_close: true } }

          before(:each) do
            datadog_tracer.trace(parent_span_name) do |span|
              @parent_span = span
              tracer.start_active_span(span_name, **options) do |scope|
                @scope = scope
              end
            end
          end

          let(:parent_datadog_span) { datadog_spans.first }
          let(:child_datadog_span) { datadog_spans.last }

          it { expect(datadog_spans).to have(2).items }
          it { expect(parent_datadog_span.name).to eq(parent_span_name) }
          it { expect(parent_datadog_span.parent_id).to eq(0) }
          it { expect(parent_datadog_span.finished?).to be(true) }
          it { expect(child_datadog_span.name).to eq(span_name) }
          it { expect(child_datadog_span.parent_id).to eq(parent_datadog_span.span_id) }
          it { expect(child_datadog_span.finished?).to be(true) }
          it { expect(child_datadog_span.trace_id).to eq(parent_datadog_span.trace_id) }
        end

        context 'followed by a Datadog span' do
          let(:child_span_name) { 'operation.bar' }
          let(:options) { { finish_on_close: true } }

          before(:each) do
            tracer.start_active_span(span_name, **options) do |scope|
              @scope = scope
              datadog_tracer.trace(child_span_name) do |span|
                @child_span = span
              end
            end
          end

          let(:parent_datadog_span) { datadog_spans.last }
          let(:child_datadog_span) { datadog_spans.first }

          it { expect(datadog_spans).to have(2).items }
          it { expect(parent_datadog_span.name).to eq(span_name) }
          it { expect(parent_datadog_span.parent_id).to eq(0) }
          it { expect(parent_datadog_span.finished?).to be(true) }
          it { expect(child_datadog_span.name).to eq(child_span_name) }
          it { expect(child_datadog_span.parent_id).to eq(parent_datadog_span.span_id) }
          it { expect(child_datadog_span.finished?).to be(true) }
          it { expect(child_datadog_span.trace_id).to eq(parent_datadog_span.trace_id) }
        end
      end

      context 'for a nested span' do
        context 'when there is an active scope' do
          context 'which is used' do
            before(:each) do
              tracer.start_active_span('operation.parent') do |parent_scope|
                tracer.start_active_span('operation.child') do |scope|
                  # Assert Datadog context integrity
                  expect(current_trace_for(scope)).to have(2).items
                  expect(current_trace_for(scope)).to include(parent_scope.span.datadog_span, scope.span.datadog_span)
                end
              end
            end

            let(:parent_datadog_span) { datadog_spans.last }
            let(:child_datadog_span) { datadog_spans.first }

            it { expect(datadog_spans).to have(2).items }
            it { expect(parent_datadog_span.name).to eq('operation.parent') }
            it { expect(parent_datadog_span.parent_id).to eq(0) }
            it { expect(parent_datadog_span.finished?).to be true }
            it { expect(child_datadog_span.name).to eq('operation.child') }
            it { expect(child_datadog_span.parent_id).to eq(parent_datadog_span.span_id) }
            it { expect(child_datadog_span.finished?).to be true }
          end

          context 'which is ignored' do
            before(:each) do
              tracer.start_active_span('operation.parent') do |_parent_scope|
                tracer.start_active_span('operation.child', ignore_active_scope: true) do |scope|
                  # Assert Datadog context integrity
                  expect(current_trace_for(scope)).to have(1).items
                  expect(current_trace_for(scope)).to include(scope.span.datadog_span)
                end
              end
            end

            let(:parent_datadog_span) { datadog_spans.last }
            let(:child_datadog_span) { datadog_spans.first }

            it { expect(datadog_spans).to have(2).items }
            it { expect(parent_datadog_span.name).to eq('operation.parent') }
            it { expect(parent_datadog_span.parent_id).to eq(0) }
            it { expect(parent_datadog_span.finished?).to be true }
            it { expect(child_datadog_span.name).to eq('operation.child') }
            it { expect(child_datadog_span.parent_id).to eq(0) }
            it { expect(child_datadog_span.finished?).to be true }
          end
        end

        context 'manually associated with child_of' do
          before(:each) do
            tracer.start_span('operation.parent').tap do |parent_span|
              tracer.start_active_span('operation.fake_parent') do |_fake_parent_span|
                tracer.start_active_span('operation.child', child_of: parent_span) do |scope|
                  # Assert Datadog context integrity
                  expect(current_trace_for(scope)).to have(2).items
                  expect(current_trace_for(scope)).to include(parent_span.datadog_span, scope.span.datadog_span)
                end
              end
            end.finish
          end

          let(:parent_datadog_span) { datadog_spans[2] }
          let(:fake_parent_datadog_span) { datadog_spans[1] }
          let(:child_datadog_span) { datadog_spans[0] }

          it { expect(datadog_spans).to have(3).items }
          it { expect(parent_datadog_span.name).to eq('operation.parent') }
          it { expect(parent_datadog_span.parent_id).to eq(0) }
          it { expect(parent_datadog_span.finished?).to be true }
          it { expect(child_datadog_span.name).to eq('operation.child') }
          it { expect(child_datadog_span.parent_id).to eq(parent_datadog_span.span_id) }
          it { expect(child_datadog_span.finished?).to be true }
          it { expect(fake_parent_datadog_span.name).to eq('operation.fake_parent') }
          it { expect(fake_parent_datadog_span.parent_id).to eq(0) }
          it { expect(fake_parent_datadog_span.finished?).to be true }
        end
      end

      context 'for sibling span' do
        before(:each) do
          tracer.start_active_span('operation.older_sibling') { |scope| }
          tracer.start_active_span('operation.younger_sibling') do |scope|
            # Assert Datadog context integrity
            expect(current_trace_for(scope)).to have(1).items
            expect(current_trace_for(scope)).to include(scope.span.datadog_span)
          end
        end

        let(:older_datadog_span) { datadog_spans.first }
        let(:younger_datadog_span) { datadog_spans.last }

        it { expect(datadog_spans).to have(2).items }
        it { expect(older_datadog_span.name).to eq('operation.older_sibling') }
        it { expect(older_datadog_span.parent_id).to eq(0) }
        it { expect(older_datadog_span.finished?).to be true }
        it { expect(younger_datadog_span.name).to eq('operation.younger_sibling') }
        it { expect(younger_datadog_span.parent_id).to eq(0) }
        it { expect(younger_datadog_span.finished?).to be true }
      end
    end
  end
end
