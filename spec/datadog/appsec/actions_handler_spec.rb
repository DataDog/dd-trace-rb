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
    let(:generate_stack_action) { { 'stack_id' => 'foo' } }
    let(:trace_op) { Datadog::Tracing::TraceOperation.new }
    let(:span_op) { Datadog::Tracing::SpanOperation.new('span_test') }
    let(:context) { OpenStruct.new(trace: trace_op, span: span_op) }
    let(:stack_trace_enabled) { true }

    let(:stack_key) { Datadog::AppSec::Ext::TAG_STACK_TRACE }
    let(:exploit_category) { Datadog::AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY }

    before do
      allow(Datadog.configuration.appsec.stack_trace).to receive(:enabled).and_return(stack_trace_enabled)
      allow(Datadog::AppSec::Context).to receive(:active).and_return(context)
      allow(Datadog::AppSec::ActionsHandler::StackTrace).to receive(:collect_stack_frames).and_return(
        ThreadBacktraceHelper.locations_inside_nested_blocks
      )
      described_class.generate_stack(generate_stack_action)
    end

    context 'when stack trace is enabled and context contains trace and span' do
      it 'adds stack trace representation to the trace' do
        test_result = trace_op.metastruct[stack_key][exploit_category]
        expect(test_result.size).to eq(1)
        expect(test_result.first.id).to eq('foo')
        expect(test_result.first.frames.size).to eq(5)
      end
    end

    context 'when stack trace is enabled and context contains only span' do
      let(:context) { OpenStruct.new(span: span_op) }

      it 'adds stack trace representation to the span' do
        test_result = span_op.metastruct[stack_key][exploit_category]
        expect(test_result.size).to eq(1)
        expect(test_result.first.id).to eq('foo')
        expect(test_result.first.frames.size).to eq(5)
      end
    end

    context 'when stack trace is disabled' do
      let(:stack_trace_enabled) { false }

      it 'does not add stack trace representation to the trace' do
        expect(trace_op.metastruct[stack_key]).to be_nil
      end
    end
  end
end
