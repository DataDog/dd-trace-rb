require 'spec_helper'

require 'logger'
require 'stringio'
require 'time'
require 'ddtrace'

RSpec.describe Datadog::Logging::RateLimitedLogger do
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

  # Ensure we restore original values after every test
  around do |example|
    Datadog::Tracer.log_limiter = Datadog::Tracer.log_limiter.tap do
      Datadog::Tracer.log_limiter = limiter

      Datadog::Tracer.log = Datadog::Tracer.log.tap do
        Datadog::Tracer.log = logger

        Datadog::Tracer.debug_logging = Datadog::Tracer.debug_logging.tap do
          Datadog.configuration.logging.rate = Datadog.configuration.logging.rate.tap do
            example.run
          end
        end
      end
    end
  end

  # DEV: In older versions of Ruby `buf.string.lines` is an Enumerator and not an array
  let(:lines) { buf.string.lines.to_a }
  let(:logger) do
    described_class.new(Datadog::Logging::Logger.new(buf)).tap do |logger|
      logger.level = log_level
    end
  end
  let(:buf) { StringIO.new }
  let(:log_level) { Logger::WARN }
  let(:limiter) { Datadog::Logging::Limiter.new }

  describe 'default logger' do
    it { expect(Datadog::Tracer.log).to_not be_nil }
    it { expect(Datadog::Tracer.log).to be(logger) }

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
        before(:each) { log_debug }
        it { expect(lines.length).to eq(0) if lines.respond_to?(:length) }
      end

      context 'debug log level' do
        let(:log_level) { Logger::DEBUG }

        before(:each) { log_debug }

        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for debug
        it do
          expect(lines[0]).to match(Regexp.new('D, \[[0-9:T.-]+ #[0-9]+\] DEBUG -- ddtrace: \[ddtrace\] ' \
                                               '\([\/a-z_]+\.rb:[0-9]+:in `log_debug\'\) debug message\n'))
        end
      end
    end

    context '#error()' do
      context 'default log level' do
        before(:each) { log_error }
        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for errors
        it do
          expect(lines[0]).to match(Regexp.new('E, \[[0-9:T.-]+ #[0-9]+\] ERROR -- ddtrace: \[ddtrace\] '\
                                               '\([\/a-z_]+\.rb:[0-9]+:in `log_error\'\) error message\n'))
        end
      end
    end

    context '#warn' do
      context '()' do
        it { expect { Datadog::Tracer.log.warn('warn message') }.to_not raise_error }
      end

      context '() { message }' do
        it { expect { Datadog::Tracer.log.warn { 'warn message' } }.to_not raise_error }
      end

      context '(progname) { message }' do
        it { expect { Datadog::Tracer.log.warn('bar') { 'warn message' } }.to_not raise_error }
      end

      context 'default log level' do
        before(:each) { log_warn }
        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] warn message\n/) }
      end

      context 'debug log level' do
        let(:log_level) { Logger::DEBUG }
        before(:each) { log_warn }

        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for errors
        it do
          expect(lines[0]).to match(Regexp.new('W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] '\
                                               '\([\/a-z_]+\.rb:[0-9]+:in `log_warn\'\) warn message\n'))
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
      # We need `Logger.new` instead of `described_class.new`
      Logger.new(buf).tap do |logger|
        logger.level = Logger::INFO
      end
    end

    # Invalid values to set
    [
      nil,
      'this is a message'
    ].each do |value|
      context 'when it is #{value.inspect}' do
        before(:each) { Datadog::Tracer.log = value }
        it { expect(Datadog::Tracer.log).to be(logger) }
      end
    end

    context '#level' do
      it { expect(Datadog::Tracer.log.level).to eq(Logger::INFO) }
    end

    context 'debug_logging enabled' do
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
      # DEV: Freeze time to ensure these all get logged into the same bucket
      before(:each) { Timecop.freeze { 10.times { log_warn } } }

      it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] warn message\n/) }
    end

    context 'after rate limit elapses' do
      before(:each) do
        # Log 5 messages in one bucket
        # DEV: Freeze time to ensure these all get logged into the same bucket
        Timecop.freeze do
          # Log 5 messages in one bucket
          5.times { log_warn }

          # Travel 5 minutes into the future, and log 5 more messages
          Timecop.travel(Time.now + 300) { 5.times { log_warn } }
        end
      end

      it { expect(lines.length).to eq(2) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] warn message\n/) }
      it do
        expect(lines[1]).to match(Regexp.new('W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] ' \
                                             'warn message, 4 additional messages skipped\n'))
      end
    end

    context 'when logging from multiple places' do
      before(:each) do
        # DEV: Freeze time to ensure these all get logged into the same bucket
        Timecop.freeze do
          10.times do
            log_warn
            log_error
          end
        end
      end

      it { expect(lines.length).to eq(2) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] warn message\n/) }
      it do
        expect(lines[1]).to match(Regexp.new('E, \[[0-9:T.-]+ #[0-9]+\] ERROR -- ddtrace: \[ddtrace\] ' \
                                             '\([\/a-z_]+\.rb:[0-9]+:in `log_error\'\) error message\n'))
      end
    end
  end
end
