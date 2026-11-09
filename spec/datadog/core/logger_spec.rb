require "spec_helper"

require "datadog/core/logger"

RSpec.describe Datadog::Core::Logger do
  describe "::new" do
    subject(:logger) { described_class.new($stdout) }

    it { is_expected.to be_a_kind_of(::Logger) }
    it { expect(logger.level).to be ::Logger::INFO }
    it { expect(logger.progname).to eq(Datadog::Core::Logger::PREFIX) }

    context "with keyword arguments" do
      subject(:logger) { described_class.new($stdout, formatter: formatter) }

      let(:formatter) { proc { |*| "formatted\n" } }

      it "passes them to ::Logger" do
        expect(logger.formatter).to be formatter
      end
    end
  end

  describe "output" do
    subject(:lines) do
      log_messages! # This is done to manipulate the stacktrace
      buffer.string.lines
    end

    let(:logger) { described_class.new(buffer) }
    let(:buffer) { StringIO.new }

    def log_messages!
      logger.debug("Debug message")
      logger.info("Info message")
      logger.warn("Warning message")
      logger.error { "Error message #1" }
      logger.error("my-progname") { "Error message #2" }
      logger.add(Logger::ERROR, "Error message #3")
    end

    context "with default settings" do
      it { is_expected.to have(5).items }

      it "produces log messages with expected format" do
        expect(lines[0]).to match(/I,.*INFO -- datadog: \[datadog\] Info message/)

        expect(lines[1]).to match(
          /W,.*WARN -- datadog: \[datadog\] Warning message/,
        )

        expect(lines[2]).to match(
          /E,.*ERROR -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Error message #1/,
        )

        expect(lines[3]).to match(
          /E,.*ERROR -- my-progname: \[datadog\] \(.*logger_spec.rb.*\) Error message #2/,
        )

        expect(lines[4]).to match(
          /E,.*ERROR -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Error message #3/,
        )
      end
    end

    context "with debug level set" do
      before { logger.level = ::Logger::DEBUG }

      it { is_expected.to have(6).items }

      it "produces log messages with expected format" do
        expect(lines[0]).to match(
          /D,.*DEBUG -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Debug message/,
        )

        expect(lines[1]).to match(
          /I,.*INFO -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Info message/,
        )

        expect(lines[2]).to match(
          /W,.*WARN -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Warning message/,
        )

        expect(lines[3]).to match(
          /E,.*ERROR -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Error message #1/,
        )

        expect(lines[4]).to match(
          /E,.*ERROR -- my-progname: \[datadog\] \(.*logger_spec.rb.*\) Error message #2/,
        )

        expect(lines[5]).to match(
          /E,.*ERROR -- datadog: \[datadog\] \(.*logger_spec.rb.*\) Error message #3/,
        )
      end

      it "logs the caller location relative to lib/datadog when the caller is in the gem" do
        lib_datadog_dir = File.expand_path("../../../lib/datadog", File.dirname(__FILE__))
        logger.instance_eval('debug("Debug message")', "#{lib_datadog_dir}/core/example.rb", 42) # rubocop:disable Style/EvalWithLocation

        expect(buffer.string).to include("[datadog] (core/example.rb:42) Debug message")
      end

      it "logs the absolute caller location when the caller is outside the gem" do
        logger.debug("Debug message")

        expect(buffer.string).to include("[datadog] (#{__FILE__}:#{__LINE__ - 2}) Debug message")
      end
    end
  end
end
