# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di/fatal_exceptions"

RSpec.describe "Datadog::DI.reraise_if_fatal" do
  describe '.reraise_if_fatal' do
    context 'when given a fatal exception' do
      [SystemExit.new, SignalException.new('TERM'), Interrupt.new, NoMemoryError.new].each do |exc|
        it "re-raises #{exc.class}" do
          expect { Datadog::DI.reraise_if_fatal(exc) }.to raise_error(exc.class)
        end
      end

      it 're-raises the same exception instance' do
        exc = SystemExit.new
        expect { Datadog::DI.reraise_if_fatal(exc) }.to raise_error { |raised| expect(raised).to equal(exc) }
      end

      it 'preserves the original backtrace when re-raising' do
        original = begin
          raise SystemExit, 'shutting down'
        rescue SystemExit => e
          e
        end

        raised = begin
          Datadog::DI.reraise_if_fatal(original)
          nil
        rescue SystemExit => e
          e
        end

        expect(raised.backtrace).to eq(original.backtrace)
      end
    end

    context 'when given a non-fatal exception' do
      [StandardError.new, RuntimeError.new, NotImplementedError.new, LoadError.new, SystemStackError.new].each do |exc|
        it "returns without raising for #{exc.class}" do
          expect { Datadog::DI.reraise_if_fatal(exc) }.not_to raise_error
        end
      end
    end
  end
end
