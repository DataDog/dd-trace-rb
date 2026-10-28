# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/rspec/support"
require "rubocop/custom_cops/diagnostic_call_rescue_cop"

RSpec.describe CustomCops::DiagnosticCallRescueCop do
  subject(:cop) { described_class.new }

  describe "blind rescues around a bare diagnostic call" do
    it "registers an offense for begin/rescue wrapping logger.debug" do
      expect_offense(<<~'RUBY')
        begin
          logger.debug("hello")
        rescue
        ^^^^^^ CustomCops/DiagnosticCallRescueCop: Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. The logger/telemetry contract is to not raise during normal use; swallowing an exception here hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or make the rescue do something meaningful (e.g. report the exception, or re-raise).
          nil
        end
      RUBY
    end

    it "registers an offense for a method-level rescue wrapping telemetry.inc" do
      expect_offense(<<~'RUBY')
        def record
          telemetry.inc(:namespace, :metric, 1)
        rescue => e
        ^^^^^^^^^^^ CustomCops/DiagnosticCallRescueCop: Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. The logger/telemetry contract is to not raise during normal use; swallowing an exception here hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or make the rescue do something meaningful (e.g. report the exception, or re-raise).
          nil
        end
      RUBY
    end

    it "registers an offense for a postfix rescue" do
      expect_offense(<<~'RUBY')
        telemetry.inc(:namespace, :metric, 1) rescue nil
                                              ^^^^^^ CustomCops/DiagnosticCallRescueCop: Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. The logger/telemetry contract is to not raise during normal use; swallowing an exception here hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or make the rescue do something meaningful (e.g. report the exception, or re-raise).
      RUBY
    end
  end

  describe "blind rescues around a blocked diagnostic call" do
    it "registers an offense for logger.debug { ... }" do
      expect_offense(<<~'RUBY')
        begin
          logger.debug { "hello" }
        rescue => e
        ^^^^^^^^^^^ CustomCops/DiagnosticCallRescueCop: Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. The logger/telemetry contract is to not raise during normal use; swallowing an exception here hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or make the rescue do something meaningful (e.g. report the exception, or re-raise).
          nil
        end
      RUBY
    end
  end

  describe "blind rescues around a guarded diagnostic call" do
    it "registers an offense for `if logger.debug? ... logger.debug(...) end`" do
      expect_offense(<<~'RUBY')
        begin
          if logger.debug?
            logger.debug("hello")
          end
        rescue
        ^^^^^^ CustomCops/DiagnosticCallRescueCop: Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. The logger/telemetry contract is to not raise during normal use; swallowing an exception here hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or make the rescue do something meaningful (e.g. report the exception, or re-raise).
          nil
        end
      RUBY
    end

    it "registers an offense for a one-line guarded form" do
      expect_offense(<<~'RUBY')
        begin
          @logger.debug(msg) if @logger.debug?
        rescue
        ^^^^^^ CustomCops/DiagnosticCallRescueCop: Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. The logger/telemetry contract is to not raise during normal use; swallowing an exception here hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or make the rescue do something meaningful (e.g. report the exception, or re-raise).
          nil
        end
      RUBY
    end
  end

  describe "non-offending patterns" do
    it "does not register an offense when the rescue branch references the exception" do
      expect_no_offenses(<<~'RUBY')
        begin
          logger.debug("hello")
        rescue => e
          telemetry.report(e, description: "hello failed")
        end
      RUBY
    end

    it "does not register an offense when the rescue branch re-raises (bare raise)" do
      expect_no_offenses(<<~'RUBY')
        begin
          logger.debug("hello")
        rescue
          raise
        end
      RUBY
    end

    it "does not register an offense when the rescue branch re-raises with an argument" do
      expect_no_offenses(<<~'RUBY')
        begin
          logger.debug("hello")
        rescue => e
          raise DI::Error, "wrapped: #{e.message}"
        end
      RUBY
    end

    it "does not register an offense when the protected body does more than the diagnostic call" do
      expect_no_offenses(<<~'RUBY')
        begin
          crashtracker.report_unhandled_exception(exception)
          logger.debug("reported")
        rescue => e
          logger.debug("failed to report: #{e.class}: #{e.message}")
        end
      RUBY
    end

    it "does not register an offense for a nested reasoned rescue (distinct-message pattern)" do
      expect_no_offenses(<<~'RUBY')
        def inc_metric(namespace, metric_name, value, tags:)
          telemetry&.inc(namespace, metric_name, value, tags: tags)
        rescue Exception => exc
          report_emission_failure(namespace, metric_name, exc)
          nil
        end

        def report_emission_failure(namespace, metric_name, exc)
          logger.debug { "di: error emitting #{namespace}.#{metric_name} metric: #{exc.class}: #{exc.message}" }
          begin
            telemetry&.report(exc, description: "Error emitting #{namespace}.#{metric_name} metric")
          rescue Exception => nested_exc
            logger.debug { "di: error reporting #{namespace}.#{metric_name} metric emission failure: #{nested_exc.class}" }
          end
        end
      RUBY
    end

    it "does not register an offense when the guard has an else branch" do
      expect_no_offenses(<<~'RUBY')
        begin
          if logger.debug?
            logger.debug("hello")
          else
            logger.info("fallback")
          end
        rescue
          nil
        end
      RUBY
    end

    it "does not register an offense for an unrelated receiver that happens to be named logger" do
      expect_no_offenses(<<~'RUBY')
        begin
          logger.flush_to_disk
        rescue
          nil
        end
      RUBY
    end

    it "does not register an offense when the rescue references the exception inside a nested block" do
      expect_no_offenses(<<~'RUBY')
        begin
          logger.debug("hello")
        rescue => e
          [1, 2].each { |i| track(e, i) }
        end
      RUBY
    end

    it "does not register an offense for a rescue with no matching diagnostic receiver" do
      expect_no_offenses(<<~'RUBY')
        begin
          do_something_risky
        rescue
          nil
        end
      RUBY
    end

    it "does not register an offense when the protected body is a multi-line diagnostic plus other logic" do
      expect_no_offenses(<<~'RUBY')
        begin
          value = compute_value
          logger.debug("value: #{value}")
        rescue
          nil
        end
      RUBY
    end
  end
end
