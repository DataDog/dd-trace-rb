require 'spec_helper'

require 'logger'
require 'stringio'
require 'time'
require 'ddtrace'

RSpec.describe Datadog::Logging::RateLimitedLogger do
  subject(:logger) do
    described_class.new(buf).tap do |logger|
      logger.level = log_level
    end
  end
  let(:buf) { StringIO.new }
  # DEV: In older versions of Ruby `buf.string.lines` is an Enumerator and not an array
  let(:lines) { buf.string.lines.to_a }
  let(:log_level) { Logger::WARN }

  # Define functions to log to ensure the caller stack is consistent between tests
  def log_warn(logger)
    logger.warn('warn message')
  end

  def log_error(logger)
    logger.error('error message')
  end

  def log_debug(logger)
    logger.debug('debug message')
  end

  after(:each) do
    Datadog::Tracer.log_limiter.reset!
  end

  describe 'defaults' do
    context '#level' do
      context 'default level' do
        it { expect(logger.level).to eq(Logger::WARN) }
        it { expect(logger.debug?).to be(false) }
        it { expect(logger.info?).to be(false) }
        it { expect(logger.warn?).to be(true) }
        it { expect(logger.error?).to be(true) }
        it { expect(logger.fatal?).to be(true) }
      end

      context 'debug level' do
        let(:log_level) { Logger::DEBUG }
        it { expect(logger.level).to eq(Logger::DEBUG) }
        it { expect(logger.debug?).to be(true) }
        it { expect(logger.info?).to be(true) }
        it { expect(logger.warn?).to be(true) }
        it { expect(logger.error?).to be(true) }
        it { expect(logger.fatal?).to be(true) }
      end
    end

    context '#debug()' do
      context 'default log level' do
        before(:each) { log_debug(logger) }
        it { expect(lines.length).to eq(0) if lines.respond_to?(:length) }
      end

      context 'debug log level' do
        let(:log_level) { Logger::DEBUG }

        before(:each) { log_debug(logger) }

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
        before(:each) { log_error(logger) }
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
        it { expect { logger.warn('warn message') }.to_not raise_error }
      end

      context '() { message }' do
        it { expect { logger.warn { 'warn message' } }.to_not raise_error }
      end

      context '(progname) { message }' do
        it { expect { logger.warn('bar') { 'warn message' } }.to_not raise_error }
      end

      context 'default log level' do
        before(:each) { log_warn(logger) }
        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] warn message\n/) }
      end

      context 'debug log level' do
        let(:log_level) { Logger::DEBUG }
        before(:each) { log_warn(logger) }

        it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
        # We add traceback information to the log line for errors
        it do
          expect(lines[0]).to match(Regexp.new('W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] '\
                                               '\([\/a-z_]+\.rb:[0-9]+:in `log_warn\'\) warn message\n'))
        end
      end
    end
  end

  describe 'rate limiting' do
    context 'when hitting rate limit' do
      # DEV: Freeze time to ensure these all get logged into the same bucket
      before(:each) { Timecop.freeze { 10.times { log_warn(logger) } } }

      it { expect(lines.length).to eq(1) if lines.respond_to?(:length) }
      it { expect(lines[0]).to match(/W, \[[0-9:T.-]+ #[0-9]+\]  WARN -- ddtrace: \[ddtrace\] warn message\n/) }
    end

    context 'after rate limit elapses' do
      before(:each) do
        # Log 5 messages in one bucket
        # DEV: Freeze time to ensure these all get logged into the same bucket
        Timecop.freeze do
          # Log 5 messages in one bucket
          5.times { log_warn(logger) }

          # Travel 5 minutes into the future, and log 5 more messages
          Timecop.travel(Time.now + 300) { 5.times { log_warn(logger) } }
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
            log_warn(logger)
            log_error(logger)
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
