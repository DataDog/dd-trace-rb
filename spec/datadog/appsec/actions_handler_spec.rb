# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

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
    let(:action_params) { { 'stack_id' => 'test-stack-id' } }
    let(:active_span) { Datadog::Tracing::Span.new('test-span') }
    let(:active_context) { instance_double(Datadog::AppSec::Context, span: active_span) }

    before do
      allow(Datadog.configuration.appsec.stack_trace).to receive(:enabled).and_return(true)
      allow(Datadog::AppSec).to receive(:active_context).and_return(active_context)
    end

    after do
      Datadog.configuration.appsec.reset!
    end

    context 'when metastruct _dd.stack tag is empty' do
      it 'adds serializable stack trace' do
        expect(active_span).to receive(:set_metastruct_tag).with(
          Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE,
          { 'exploit' => [instance_of(Datadog::AppSec::ActionsHandler::SerializableBacktrace)] }
        )

        described_class.generate_stack(action_params)
      end
    end

    context 'when metastruct _dd.stack tag already has 1 element' do
      before do
        active_span.set_metastruct_tag(
          Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE,
          { 'exploit' => [1] }
        )
      end

      it 'adds new stack trace to existing stack trace' do
        expect(active_span).to receive(:set_metastruct_tag).with(
          Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE,
          { 'exploit' => [1, instance_of(Datadog::AppSec::ActionsHandler::SerializableBacktrace)] }
        )

        described_class.generate_stack(action_params)
      end
    end

    context 'when metastruct _dd.stack tag already has 2 elements' do
      before do
        active_span.set_metastruct_tag(
          Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE,
          { 'exploit' => [1, 2] }
        )
      end

      it 'does not add stack trace to metastruct' do
        expect { described_class.generate_stack(action_params) }
          .not_to(change { active_span.get_metastruct_tag(Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE) })
      end
    end

    context 'when metastruct _dd.stack tag already has 2 elements, but max_stack_traces is set to zero' do
      before do
        Datadog.configuration.appsec.stack_trace.max_stack_traces = 0

        active_span.set_metastruct_tag(
          Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE,
          { 'exploit' => [1, 2] }
        )
      end

      it 'adds new stack trace to existing stack trace' do
        expect(active_span).to receive(:set_metastruct_tag).with(
          Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE,
          { 'exploit' => [1, 2, instance_of(Datadog::AppSec::ActionsHandler::SerializableBacktrace)] }
        )

        described_class.generate_stack(action_params)
      end
    end

    it 'does nothing when stack_id is missing' do
      expect { described_class.generate_stack({}) }
        .not_to(change { active_span.get_metastruct_tag(Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE) })
    end

    it 'does nothing when stack trace is disabled' do
      allow(Datadog.configuration.appsec.stack_trace).to receive(:enabled).and_return(false)

      expect { described_class.generate_stack({}) }
        .not_to(change { active_span.get_metastruct_tag(Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE) })
    end

    it 'does nothing when there is no active span' do
      allow(active_context).to receive(:span).and_return(nil)

      expect { described_class.generate_stack({}) }
        .not_to(change { active_span.get_metastruct_tag(Datadog::AppSec::Ext::TAG_METASTRUCT_STACK_TRACE) })
    end
  end
end
