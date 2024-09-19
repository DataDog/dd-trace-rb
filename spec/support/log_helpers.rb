module LogHelpers
  def without_warnings(&block)
    LogHelpers.without_warnings(&block)
  end

  def self.without_warnings
    v = $VERBOSE
    $VERBOSE = nil
    begin
      yield
    ensure
      $VERBOSE = v
    end
  end

  def without_errors
    level = Datadog.logger.level
    Datadog.configure { |c| c.logger.level = Logger::FATAL }

    begin
      yield
    ensure
      Datadog.configure { |c| c.logger.level = level }
    end
  end

  RSpec::Matchers.define :have_lazy_debug_logged do |expected|
    match do |actual|
      expect(actual).to have_received(:debug) do |*_args, &block|
        result =  case expected
                  when String
                    begin
                      expect(block.call).to include(expected)
                    rescue RSpec::Expectations::ExpectationNotMetError
                      false
                    end
                  when Regexp
                    begin
                      expect(block.call).to match(expected)
                    rescue RSpec::Expectations::ExpectationNotMetError
                      false
                    end
                  else
                    raise "Don't know how to match '#{expected}'."
                  end

        return true if result
      end

      false
    end
  end

  shared_context 'tracer logging' do
    let(:log_buffer) { StringIO.new }

    before do
      @default_logger = Datadog.logger
      Datadog.configure do |c|
        c.logger.instance = Datadog::Core::Logger.new(log_buffer)
        c.logger.level = ::Logger::WARN
      end
    end

    after do
      Datadog.configure do |c|
        c.logger.instance = @default_logger
        c.diagnostics.debug = false
      end
    end
  end

  # Matches Datadog.logger.warn messages
  RSpec::Matchers.define :emit_deprecation_warning do |expected|
    match do |actual|
      captured_log_entries = []
      allow(Datadog.logger).to receive(:warn) do |arg, &block|
        captured_log_entries << if block
                                  block.call
                                else
                                  arg
                                end
      end

      actual.call

      @actual = captured_log_entries.join('\n')

      # Matches any output with the word deprecation (or equivalent variants)
      # in case no expectation is specified.
      expected ||= /deprecat(e|ion)/i

      values_match?(expected, @actual)
    end

    def failure_message
      "expected Datadog.logger.warn output #{description_of @actual} to #{description}".dup
    end

    def failure_message_when_negated
      "expected Datadog.logger.warn output #{description_of @actual} not to #{description}".dup
    end

    diffable

    # Only allow matching with blocks
    supports_block_expectations
    def supports_value_expectations?
      false
    end
  end
end
