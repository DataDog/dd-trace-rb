# typed: ignore
# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/reactive/operation'

RSpec.describe Datadog::AppSec::Reactive::Operation do
  after(:each) do
    Thread.current[:datadog_security_active_operation] = nil
  end

  context 'initialize' do
    it 'set current datadog_security_active_operation thread variable for the duration of the block' do
      active_operation = Thread.current[:datadog_security_active_operation]
      expect(active_operation).to be_nil
      described_class.new('test') do |op|
        expect(Thread.current[:datadog_security_active_operation]).to eq(op)
      end
      expect(active_operation).to be_nil
    end

    it 'set parent attrribute and set datadog_security_active_operation to parent at the end of the block' do
      parent_operation = described_class.new('parent_test')
      described_class.new('test', parent_operation) do |op|
        expect(Thread.current[:datadog_security_active_operation]).to eq(op)
      end
      expect(Thread.current[:datadog_security_active_operation]).to eq(parent_operation)
    end

    it 'creates a new Reactive instance when no reactive instance provided' do
      described_class.new('test') do |op|
        expect(op.reactive).to be_a Datadog::AppSec::Reactive::Engine
      end
    end

    it 'uses provided reactive instance' do
      reactive_instance = Datadog::AppSec::Reactive::Engine.new
      described_class.new('test', nil, reactive_instance) do |op|
        expect(op.reactive).to eq(reactive_instance)
      end
    end

    it 'uses reactive instance from parent' do
      parent_operation = described_class.new('parent_test')
      described_class.new('test', parent_operation) do |op|
        expect(op.reactive).to eq(parent_operation.reactive)
      end
    end

    it 'uses reactive instance over parent engine' do
      reactive_instance = Datadog::AppSec::Reactive::Engine.new
      parent_operation = described_class.new('parent_test')
      described_class.new('test', parent_operation, reactive_instance) do |op|
        expect(op.reactive).to eq(reactive_instance)
      end
    end
  end

  context 'subscribe' do
    it 'delegates to reactive engine' do
      operation = described_class.new('test')
      expect(operation.reactive).to receive(:subscribe).with([:a, :b, :c])
      operation.subscribe([:a, :b, :c]) do
        1 + 1
      end
    end
  end

  context 'publish' do
    it 'delegates to reactive engine' do
      operation = described_class.new('test')
      expect(operation.reactive).to receive(:publish).with(:a, "hello world")
      operation.publish(:a, "hello world")
    end
  end

  context 'finalize' do
    it 'set datadog_security_active_operation to parent' do
      parent_operation = described_class.new('parent_test')
      operation = described_class.new('test', parent_operation)
      expect(Thread.current[:datadog_security_active_operation]).to eq(parent_operation)
      parent_operation.finalize
      # The parent of parent_operation is nil because is the top operation
      expect(Thread.current[:datadog_security_active_operation]).to be_nil
    end
  end
end
