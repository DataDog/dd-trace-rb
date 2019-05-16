require 'spec_helper'

require 'logger'
require 'stringio'
require 'time'
require 'ddtrace'

# Define functions to log to ensure the caller stack is consistent between tests
def log_warn
  Datadog::Tracer.log.warn('warn message')
end

def log_error
  Datadog::Tracer.log.error('error message')
end

def log_debug
  Datadog::Tracer.log.debug('debug message')
end

RSpec.describe Datadog::Logger do
  default_logger = Datadog::Tracer.log
  default_logging_rate = Datadog.configuration.logging_rate

  subject(:lines) { buf.string.lines }
  let(:logger) do
    logger = described_class.new(buf)
    logger.level = log_level

    logger
  end
  let(:buf) { StringIO.new }
  let(:log_level) { Logger::WARN }

  before(:each) { Datadog::Tracer.log = logger }
  after(:each) do
    Datadog::Tracer.log = default_logger
    Datadog.configuration.logging_rate = default_logging_rate
  end

  describe 'default logger' do
    it { expect(Datadog::Tracer.log).to_not be_nil }
    it { expect(Datadog::Tracer.log).to be(logger) }
    it { expect(Datadog::Tracer.log).to_not be(default_logger) }

    context '#level' do
      context 'default level' do
        it { expect(Datadog::Tracer.log.level).to eq(Logger::WARN) }
        it { expect(Datadog::Tracer.log.debug?).to be(false) }
        it { expect(Datadog::Tracer.log.info?).to be(false) }
        it { expect(Datadog::Tracer.log.warn?).to be(true) }
        it { expect(Datadog::Tracer.log.error?).to be(true) }
        it { expect(Datadog::Tracer.log.fatal?).to be(true) }
      end

      context 'debug level' do
        let(:log_level) { Logger::DEBUG }
        it { expect(Datadog::Tracer.log.level).to eq(Logger::DEBUG) }
        it { expect(Datadog::Tracer.log.debug?).to be(true) }
        it { expect(Datadog::Tracer.log.info?).to be(true) }
        it { expect(Datadog::Tracer.log.warn?).to be(true) }
        it { expect(Datadog::Tracer.log.error?).to be(true) }
        it { expect(Datadog::Tracer.log.fatal?).to be(true) }
      end
    end

    context '#debug()' do
      context 'default log level' do
        before(:each) { log_debug() }
        it { expect(lines.length).to eq(0) if lines.respond_to?(:length) }
      end

      context 'debug log level' do
        let(:log_level) { Logger::DEBUG }

        before(:each) { log_debug() }

        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for debug
        it do
          expect(lines[0]).to(
            match(
              %r{D, \[[0-9:T.-]+ #[0-9]+\] DEBUG -- \[ddtrace\] \([\/a-z_]+\.rb:[0-9]+:in `log_debug'\) debug message: \n}
            )
          )
        end
      end
    end

    context '#error()' do
      context 'default log level' do
        before(:each) { log_error() }
        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for errors
        it do
          expect(lines[0]).to(
            match(
              %r{E, \[[0-9:T.-]+ #[0-9]+\] ERROR -- \[ddtrace\] \([\/a-z_]+\.rb:[0-9]+:in `log_error'\) error message: \n}
            )
          )
        end
      end
    end

    context '#warn' do
      context '()' do
        it { expect { Datadog::Tracer.log.warn('warn message') }.to_not raise_error }
      end

      context '() { message }' do
        it { expect { Datadog::Tracer.log.warn() { 'warn message' } }.to_not raise_error }
      end

      context '(progname) { message }' do
        it { expect { Datadog::Tracer.log.warn('bar') { 'warn message' } }.to_not raise_error }
      end

      context 'default log level' do
        before(:each) { log_warn() }
        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- \[ddtrace\] warn message: \n/) }
      end

      context 'debug log level' do
        let(:log_level) { Logger::DEBUG }
        before(:each) { log_warn() }

        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for errors
        it do
          expect(lines[0]).to(
            match(
              %r{W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- \[ddtrace\] \([\/a-z_]+\.rb:[0-9]+:in `log_warn'\) warn message: \n}
            )
          )
        end
      end
    end

    context 'debug_logging enabled' do
      after(:each) { Datadog::Tracer.debug_logging = false }

      it do
        Datadog::Tracer.debug_logging = true
        expect(Datadog::Tracer.log.level).to eq(Logger::DEBUG)

        Datadog::Tracer.debug_logging = false
        expect(Datadog::Tracer.log.level).to eq(Logger::WARN)
      end
    end
  end

  describe 'custom logger' do
    let(:logger) do
      logger = Logger.new(buf)
      logger.level = Logger::INFO

      logger
    end

    # Invalid values to set
    [
      nil,
      'this is a message'
    ].each do |value|
      context 'when it is #{value.inspect}' do
        let(:logger) { value }

        it { expect(Datadog::Tracer.log).to be(default_logger) }
      end
    end

    context '#level' do
      it { expect(Datadog::Tracer.log.level).to eq(Logger::INFO) }
    end

    context 'debug_logging enabled' do
      after(:each) { Datadog::Tracer.debug_logging = false }

      context 'when enabling' do
        it do
          Datadog::Tracer.debug_logging = true
          expect(Datadog::Tracer.log.level).to eq(Logger::DEBUG)

          Datadog::Tracer.debug_logging = false
          expect(Datadog::Tracer.log.level).to eq(Logger::DEBUG)
        end
      end

      context 'when disabling' do
        it do
          # Assert we are not enabled and have the default log level
          expect(Datadog::Tracer.debug_logging).to be(false)
          expect(Datadog::Tracer.log.level).to eq(Logger::INFO)

          # Assert manually disabling it does not change log level
          Datadog::Tracer.debug_logging = false
          expect(Datadog::Tracer.log.level).to eq(Logger::INFO)
        end
      end
    end
  end

  describe 'rate limiting' do
    context 'when hitting rate limit' do
      before(:each) do
        # Stub Time.now to ensure it always returns the same value
        #   so we stay in the same time bucket and everything gets grouped
        allow(Time).to receive(:now).and_return Time.at(1550000000)

        i = 0
        while i < 10
          log_warn()
          i += 1
        end
      end

      it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- \[ddtrace\] warn message: \n/) }
    end

    context 'after rate limit elapses' do
      before(:each) do
        # Log 5 messages in one bucket
        allow(Time).to receive(:now).and_return Time.at(1660000000)
        i = 0
        while i < 5
          log_warn()
          i += 1
        end

        # Log 5 more messages in another bucket
        allow(Time).to receive(:now).and_return Time.at(1670000000)
        i = 0
        while i < 5
          log_warn()
          i += 1
        end
      end

      it { expect(lines.length).to eq(2) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- \[ddtrace\] warn message: \n/) }
      it do
        expect(lines[1]).to(
          match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- \[ddtrace\] warn message: , 4 additional messages skipped\n/)
        )
      end
    end

    context 'when logging from multiple places' do
      before(:each) do
        # Stub Time.now to ensure it always returns the same value
        #   so we stay in the same time bucket and everything gets grouped
        allow(Time).to receive(:now).and_return Time.at(1580000000)

        i = 0
        while i < 10
          log_warn()
          log_error()
          i += 1
        end
      end

      it { expect(lines.length).to eq(2) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- \[ddtrace\] warn message: \n/) }
      it do
        expect(lines[1]).to(
          match(
            %r{E, \[[0-9:T.-]+ #[0-9]+\] ERROR -- \[ddtrace\] \([\/a-z_]+\.rb:[0-9]+:in `log_error'\) error message: \n}
          )
        )
      end
    end
  end
end
