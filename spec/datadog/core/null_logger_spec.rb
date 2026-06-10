# frozen_string_literal: true

require 'datadog/core/null_logger'

RSpec.describe 'Datadog::Core::NULL_LOGGER' do
  subject(:null_logger) { Datadog::Core::NULL_LOGGER }

  it 'is a Logger instance' do
    expect(null_logger).to be_a(::Logger)
  end

  it 'is frozen' do
    expect(null_logger).to be_frozen
  end

  it 'is the same object across reads (process-wide singleton)' do
    expect(Datadog::Core::NULL_LOGGER).to equal(null_logger)
  end

  describe 'log methods' do
    # Each level must accept both a positional message and a block form, and
    # return without raising. Frozen-ness must not break dispatch to @logdev.
    %i[debug info warn error fatal unknown].each do |level|
      it "accepts a #{level} call with a string message" do
        expect { null_logger.public_send(level, 'message') }.not_to raise_error
      end

      it "accepts a #{level} call with a block" do
        expect { null_logger.public_send(level) { 'message' } }.not_to raise_error
      end
    end

    it 'accepts add/log calls' do
      expect { null_logger.add(::Logger::WARN, 'message') }.not_to raise_error
      expect { null_logger.log(::Logger::INFO, 'message') }.not_to raise_error
    end
  end

  describe 'discarding behavior' do
    # Sanity check: nothing observable is emitted. The underlying device is
    # IO::NULL, which silently accepts and drops all writes.
    it 'does not write to STDOUT or STDERR' do
      expect { null_logger.warn('should not appear') }.not_to output.to_stdout
      expect { null_logger.error('should not appear') }.not_to output.to_stderr
    end
  end
end
