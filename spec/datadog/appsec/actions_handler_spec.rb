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
      expect(described_class).to(
        receive(:generate_stack).with(generate_stack_action['generate_stack']).and_call_original
      )

      described_class.handle(generate_stack_action)
    end

    it 'calls generate_schema with action parameters' do
      expect(described_class).to(
        receive(:generate_schema).with(generate_schema_action['generate_schema']).and_call_original
      )

      described_class.handle('generate_schema' => generate_schema_action['generate_schema'])
    end

    it 'calls redirect_request with action parameters' do
      expect(described_class).to(
        receive(:redirect_request).with(redirect_request_action['redirect_request']).and_call_original
      )

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(redirect_request_action)
      end
    end

    it 'calls block_request with action parameters' do
      expect(described_class).to(
        receive(:block_request).with(block_request_action['block_request']).and_call_original
      )

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(block_request_action)
      end
    end

    it 'calls redirect_request only when both block_request and redirect_request are present' do
      expect(described_class).to(
        receive(:redirect_request).with(redirect_request_action['redirect_request']).and_call_original
      )
      expect(described_class).not_to receive(:block_request)

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(**block_request_action, **redirect_request_action)
      end
    end

    it 'calls both generate_stack and generate_schema when both are present' do
      expect(described_class).to(
        receive(:generate_stack).with(generate_stack_action['generate_stack']).and_call_original
      )
      expect(described_class).to(
        receive(:generate_schema).with(generate_schema_action['generate_schema']).and_call_original
      )

      described_class.handle(**generate_stack_action, **generate_schema_action)
    end

    it 'calls both generate_stack and block_request when both are present' do
      expect(described_class).to(
        receive(:generate_stack).with(generate_stack_action['generate_stack']).and_call_original
      )
      expect(described_class).to(
        receive(:block_request).with(block_request_action['block_request']).and_call_original
      )

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(**generate_stack_action, **block_request_action)
      end
    end

    it 'calls both generate_stack and redirect_request when both are present' do
      expect(described_class).to(
        receive(:generate_stack).with(generate_stack_action['generate_stack']).and_call_original
      )
      expect(described_class).to(
        receive(:redirect_request).with(redirect_request_action['redirect_request']).and_call_original
      )

      catch(Datadog::AppSec::Ext::INTERRUPT) do
        described_class.handle(**generate_stack_action, **redirect_request_action)
      end
    end
  end
end
