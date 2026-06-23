require 'spec_helper'
require 'datadog/symbol_database/logger'
require 'datadog/core/configuration'
require 'logger'

RSpec.describe Datadog::SymbolDatabase::Logger do
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.internal.trace_logging = trace_logging
    end
  end
  let(:trace_logging) { false }
  let(:target) { instance_double(::Logger, debug: nil, warn: nil) }
  let(:wrapper) { described_class.new(settings, target) }

  describe '#debug' do
    it 'forwards a positional message to the target' do
      expect(target).to receive(:debug).with('hello')
      wrapper.debug('hello')
    end

    it 'forwards a block to the target' do
      block = -> { 'hello' }
      expect(target).to receive(:debug) do |&b|
        expect(b).to be(block)
      end
      wrapper.debug(&block)
    end

    it 'returns nil' do
      expect(wrapper.debug('hello')).to be_nil
    end

    context 'when the target raises' do
      before { allow(target).to receive(:debug).and_raise(RuntimeError.new('logger boom')) }

      it 'swallows the exception' do
        expect { wrapper.debug('hello') }.not_to raise_error
      end

      it 'returns nil' do
        expect(wrapper.debug('hello')).to be_nil
      end

      it 'swallows the exception when given a block' do
        expect { wrapper.debug { 'hello' } }.not_to raise_error
      end
    end
  end

  describe '#warn' do
    it 'forwards a positional message to the target' do
      expect(target).to receive(:warn).with('hello')
      wrapper.warn('hello')
    end

    it 'forwards a block to the target' do
      block = -> { 'hello' }
      expect(target).to receive(:warn) do |&b|
        expect(b).to be(block)
      end
      wrapper.warn(&block)
    end

    context 'when the target raises' do
      before { allow(target).to receive(:warn).and_raise(RuntimeError.new('logger boom')) }

      it 'swallows the exception' do
        expect { wrapper.warn('hello') }.not_to raise_error
      end

      it 'swallows the exception when given a block' do
        expect { wrapper.warn { 'hello' } }.not_to raise_error
      end
    end
  end

  describe '#trace' do
    context 'when trace_logging is disabled (default)' do
      let(:trace_logging) { false }

      it 'is a no-op' do
        expect(target).not_to receive(:debug)
        wrapper.trace { 'hello' }
      end
    end

    context 'when trace_logging is enabled' do
      let(:trace_logging) { true }

      it 'forwards the block to debug' do
        block = -> { 'hello' }
        expect(target).to receive(:debug) do |&b|
          expect(b).to be(block)
        end
        wrapper.trace(&block)
      end

      context 'when the target raises' do
        before { allow(target).to receive(:debug).and_raise(RuntimeError.new('logger boom')) }

        it 'swallows the exception' do
          expect { wrapper.trace { 'hello' } }.not_to raise_error
        end
      end
    end
  end
end
