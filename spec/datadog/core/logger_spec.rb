require 'spec_helper'

require 'datadog/core/logger'

RSpec.describe Datadog::Core::Logger do
  describe '::new' do
    subject(:logger) { described_class.new($stdout) }

    it { is_expected.to be_a_kind_of(::Logger) }
    it { expect(logger.level).to be ::Logger::INFO }
    it { expect(logger.progname).to eq(Datadog::Core::Logger::PREFIX) }
  end

  describe 'output' do
    subject(:lines) do
      log_messages! # This is done to manipulate the stacktrace
      buffer.string.lines
    end

    let(:logger) { described_class.new(buffer) }
    let(:buffer) { StringIO.new }

    def log_messages!
      logger.debug('Debug message')
      logger.info('Info message')
      logger.warn('Warning message')
      logger.error { 'Error message #1' }
      logger.error('my-progname') { 'Error message #2' }
      logger.add(Logger::ERROR, 'Error message #3')
    end

    context 'with default settings' do
      it { is_expected.to have(5).items }

      it 'produces log messages with expected format' do
        expect(lines[0]).to match(/I,.*INFO -- ddtrace: \[ddtrace\] Info message/)

        expect(lines[1]).to match(
          /W,.*WARN -- ddtrace: \[ddtrace\] Warning message/
        )

        expect(lines[2]).to match(
          /E,.*ERROR -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Error message #1/
        )

        expect(lines[3]).to match(
          /E,.*ERROR -- my-progname: \[ddtrace\] \(.*logger_spec.rb.*\) Error message #2/
        )

        expect(lines[4]).to match(
          /E,.*ERROR -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Error message #3/
        )
      end
    end

    context 'with debug level set' do
      before { logger.level = ::Logger::DEBUG }

      it { is_expected.to have(6).items }

      it 'produces log messages with expected format' do
        expect(lines[0]).to match(
          /D,.*DEBUG -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Debug message/
        )

        expect(lines[1]).to match(
          /I,.*INFO -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Info message/
        )

        expect(lines[2]).to match(
          /W,.*WARN -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Warning message/
        )

        expect(lines[3]).to match(
          /E,.*ERROR -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Error message #1/
        )

        expect(lines[4]).to match(
          /E,.*ERROR -- my-progname: \[ddtrace\] \(.*logger_spec.rb.*\) Error message #2/
        )

        expect(lines[5]).to match(
          /E,.*ERROR -- ddtrace: \[ddtrace\] \(.*logger_spec.rb.*\) Error message #3/
        )
      end
    end
  end
end
