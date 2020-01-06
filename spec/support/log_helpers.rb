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
    level = Datadog::Logger.log.level
    Datadog::Logger.log.level = Logger::FATAL
    begin
      yield
    ensure
      Datadog::Logger.log.level = level
    end
  end

  shared_context 'tracer logging' do
    let(:log_buffer) { StringIO.new }

    before(:each) do
      @default_logger = Datadog::Logger.log
      Datadog::Logger.log = Datadog::Logger.new(log_buffer)
      Datadog::Logger.log.level = ::Logger::WARN
    end

    after(:each) do
      Datadog::Logger.log = @default_logger
    end

    # Checks buffer to see if it contains lines that match all patterns.
    # Limited to only checking for one kind of message.
    RSpec::Matchers.define :contain_line_with do |*patterns|
      attr_accessor \
        :comparison,
        :repetitions

      match do |buffer|
        repetitions ||= 1

        # Creates a Hash that counts number of matches per pattern e.g. 'a' => 0, 'b' => 0
        pattern_matches = Hash[patterns.zip(Array.new(patterns.length) { 0 })]

        # Test below iterates on lines, this is required for Ruby 1.9 backward compatibility.
        # Scans each pattern against each line, increments count if it matches.
        lines = buffer.string.lines
        lines.each do |line|
          pattern_matches.keys.each do |pattern|
            pattern_matches[pattern] += 1 if line.match(pattern)
          end
        end

        # If all patterns were matched for required number of repetitions: success.
        patterns_match_expectations = pattern_matches.values.all? do |value|
          case comparison
          when :gte
            value >= repetitions
          when :lte
            value <= repetitions
          else
            value == repetitions
          end
        end

        expect(patterns_match_expectations).to be true
      end

      chain :at_least do |count|
        @repetitions = count
        @comparison = :gte
      end

      chain :no_more_than do |count|
        @repetitions = count
        @comparison = :lte
      end

      chain :exactly do |count|
        @repetitions = count
      end

      chain :times do
        # Do nothing
      end

      chain :once do
        @repetitions = 1
      end
    end
  end
end
