# frozen_string_literal: true

require 'ostruct'

require 'datadog/appsec/ext'
require 'datadog/appsec/spec_helper'
require 'support/thread_backtrace_helpers'

RSpec.describe Datadog::AppSec::ActionsHandler do
  describe '.handle' do
    let(:generate_stack_action) do
      { 'generate_stack' => { 'stack_id' => 'foo' } }
    end

    let(:generate_schema_action) do
      { 'generate_schema' => {} }
    end

    let(:redirect_request_action) do
      { 'redirect_request' => { 'status_code' => '303', 'location' => 'http://example.com' } }
    end

    let(:block_request_action) do
      { 'block_request' => { 'status_code' => '403', 'type' => 'auto' } }
    end

    it 'calls generate_stack with action parameters' do
      expect(described_class).to receive(:generate_stack)
        .with(generate_stack_action['generate_stack']).and_call_original

      described_class.handle(generate_stack_action)
    end

    it 'calls generate_schema with action parameters' do
      expect(described_class).to receive(:generate_schema)
        .with(generate_schema_action['generate_schema']).and_call_original

      described_class.handle('generate_schema' => generate_schema_action['generate_schema'])
    end

    it 'calls redirect_request with action parameters' do
      expect(described_class).to receive(:interrupt_execution)
        .with(redirect_request_action['redirect_request']).and_call_original

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(redirect_request_action)
      end
    end

    it 'calls block_request with action parameters' do
      expect(described_class).to receive(:interrupt_execution)
        .with(block_request_action['block_request']).and_call_original

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(block_request_action)
      end
    end

    it 'calls redirect_request only when both block_request and redirect_request are present' do
      expect(described_class).to receive(:interrupt_execution)
        .with(redirect_request_action['redirect_request']).and_call_original

      expect(described_class).not_to receive(:interrupt_execution)

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(block_request_action.merge(redirect_request_action))
      end
    end

    it 'calls both generate_stack and generate_schema when both are present' do
      expect(described_class).to receive(:generate_stack)
        .with(generate_stack_action['generate_stack']).and_call_original

      expect(described_class).to receive(:generate_schema)
        .with(generate_schema_action['generate_schema']).and_call_original

      described_class.handle(generate_stack_action.merge(generate_schema_action))
    end

    it 'calls both generate_stack and block_request when both are present' do
      expect(described_class).to receive(:generate_stack)
        .with(generate_stack_action['generate_stack']).and_call_original

      expect(described_class).to receive(:interrupt_execution)
        .with(block_request_action['block_request']).and_call_original

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(generate_stack_action.merge(block_request_action))
      end
    end

    it 'calls both generate_stack and redirect_request when both are present' do
      expect(described_class).to receive(:generate_stack)
        .with(generate_stack_action['generate_stack']).and_call_original

      expect(described_class).to receive(:interrupt_execution)
        .with(redirect_request_action['redirect_request']).and_call_original

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(generate_stack_action.merge(redirect_request_action))
      end
    end
  end

  describe '.generate_stack' do
    before do
      allow(Datadog::AppSec::ActionsHandler::StackTraceCollection).to receive(:collect).and_return(
        [
          {
            id: 0,
            text: "/app/spec/support/thread_backtrace_helpers.rb:12:in `block in locations_inside_nested_blocks'",
            file: '/app/spec/support/thread_backtrace_helpers.rb',
            line: 12,
            function: 'block in locations_inside_nested_blocks'
          }
        ]
      )
    end

    context 'when stack trace is enabled and context contains trace and span' do
      let(:span_metastruct) { {} }

      let(:span_op) do
        instance_double(
          Datadog::Tracing::SpanOperation,
          metastruct: Datadog::Tracing::Metadata::Metastruct.new(span_metastruct)
        )
      end

      let(:trace_metastruct) { {} }

      let(:trace_op) do
        instance_double(
          Datadog::Tracing::TraceOperation,
          metastruct: Datadog::Tracing::Metadata::Metastruct.new(trace_metastruct)
        )
      end

      let(:context) { instance_double(Datadog::AppSec::Context, trace: trace_op, span: span_op) }

      before { allow(Datadog::AppSec).to receive(:active_context).and_return(context) }

      it 'adds stack trace to the trace' do
        described_class.generate_stack({ 'stack_id' => 'foo' })

        trace_op_result = trace_op.metastruct.dig(
          Datadog::AppSec::Ext::TAG_STACK_TRACE,
          Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
        )
        expect(trace_op_result.size).to eq(1)
        expect(trace_op_result.first[:id]).to eq('foo')
        expect(trace_op_result.first[:frames].size).to eq(1)
      end

      context 'when max_collect is 2' do
        context 'when max_collect is 2 with two elements contained in same group in trace' do
          before { allow(Datadog.configuration.appsec.stack_trace).to receive(:max_collect).and_return(2) }

          let(:trace_metastruct) do
            {
              Datadog::AppSec::Ext::TAG_STACK_TRACE => {
                Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY => [1, 2]
              }
            }
          end

          it 'does not add stack trace to the trace nor the span' do
            described_class.generate_stack({ 'stack_id' => 'foo' })

            trace_op_result = trace_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(trace_op_result.size).to eq(2)
            expect(trace_op_result[0]).to eq(1)
            expect(trace_op_result[1]).to eq(2)
            span_op_result = span_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(span_op_result).to be_nil
          end
        end

        context 'when max_collect is 2 with two elements contained in same group in span' do
          before { allow(Datadog.configuration.appsec.stack_trace).to receive(:max_collect).and_return(2) }

          let(:span_metastruct) do
            {
              Datadog::AppSec::Ext::TAG_STACK_TRACE => {
                Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY => [1, 2]
              }
            }
          end

          it 'does not add stack trace to the trace nor the span' do
            described_class.generate_stack({ 'stack_id' => 'foo' })

            span_op_result = span_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(span_op_result.size).to eq(2)
            expect(span_op_result[0]).to eq(1)
            expect(span_op_result[1]).to eq(2)
            trace_op_result = trace_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(trace_op_result).to be_nil
          end
        end

        context 'when max_collect is 2 with one element contained in same group in span and trace' do
          before { allow(Datadog.configuration.appsec.stack_trace).to receive(:max_collect).and_return(2) }

          let(:trace_metastruct) do
            {
              Datadog::AppSec::Ext::TAG_STACK_TRACE => {
                Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY => [1]
              }
            }
          end

          let(:span_metastruct) do
            {
              Datadog::AppSec::Ext::TAG_STACK_TRACE => {
                Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY => [2]
              }
            }
          end

          it 'does not add stack trace to the trace nor the span' do
            described_class.generate_stack({ 'stack_id' => 'foo' })

            trace_op_result = trace_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(trace_op_result.size).to eq(1)
            expect(trace_op_result.first).to eq(1)
            span_op_result = span_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(span_op_result.size).to eq(1)
            expect(span_op_result.first).to eq(2)
          end
        end

        context 'when max_collect is 2 with two elements contained in different group in trace' do
          before { allow(Datadog.configuration.appsec.stack_trace).to receive(:max_collect).and_return(2) }

          let(:trace_metastruct) do
            {
              Datadog::AppSec::Ext::TAG_STACK_TRACE => {
                'other_group' => [1, 2]
              }
            }
          end

          it 'does add stack trace to the trace' do
            described_class.generate_stack({ 'stack_id' => 'foo' })

            trace_op_result = trace_op.metastruct.dig(
              Datadog::AppSec::Ext::TAG_STACK_TRACE,
              Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
            )
            expect(trace_op_result.size).to eq(1)
            expect(trace_op_result.first[:id]).to eq('foo')
          end
        end
      end
    end

    context 'when stack trace is enabled and context contains only span' do
      before { allow(Datadog::AppSec).to receive(:active_context).and_return(context) }

      let(:span_op) do
        instance_double(
          Datadog::Tracing::SpanOperation,
          metastruct: Datadog::Tracing::Metadata::Metastruct.new({})
        )
      end

      let(:context) { instance_double(Datadog::AppSec::Context, trace: nil, span: span_op) }

      it 'adds stack trace to the span' do
        described_class.generate_stack({ 'stack_id' => 'foo' })

        test_result = span_op.metastruct.dig(
          Datadog::AppSec::Ext::TAG_STACK_TRACE,
          Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
        )
        expect(test_result.size).to eq(1)
        expect(test_result.first[:id]).to eq('foo')
        expect(test_result.first[:frames].size).to eq(1)
      end
    end

    context 'when stack trace is disabled' do
      before { allow(Datadog.configuration.appsec.stack_trace).to receive(:enabled).and_return(false) }

      let(:trace_op) do
        instance_double(
          Datadog::Tracing::TraceOperation,
          metastruct: Datadog::Tracing::Metadata::Metastruct.new({})
        )
      end

      let(:context) { instance_double(Datadog::AppSec::Context, trace: trace_op, span: nil) }

      it 'does not add stack trace to the trace' do
        described_class.generate_stack({ 'stack_id' => 'foo' })

        expect(trace_op.metastruct[Datadog::AppSec::Ext::TAG_STACK_TRACE]).to be_nil
      end
    end
  end
end
