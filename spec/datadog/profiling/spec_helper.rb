require "datadog/profiling"
if Datadog::Profiling.supported?
  require "datadog/profiling/pprof/pprof_pb"
  require "zstd-ruby"
end

module ProfileHelpers
  Sample = Struct.new(:locations, :values, :labels) do |_sample_class| # rubocop:disable Lint/StructNewOverride
    def value?(type)
      (values[type] || 0) > 0
    end

    def has_location?(path:, line:)
      locations.any? do |location|
        location.path == path && location.lineno == line
      end
    end
  end
  Frame = Struct.new(:base_label, :path, :lineno)

  def skip_if_profiling_not_supported(testcase)
    testcase.skip("Profiling is not supported on JRuby") if PlatformHelpers.jruby?
    testcase.skip("Profiling is not supported on TruffleRuby") if PlatformHelpers.truffleruby?

    # Profiling is not officially supported on macOS due to missing libdatadog binaries,
    # but it's still useful to allow it to be enabled for development.
    # if PlatformHelpers.mac? && ENV["DD_PROFILING_MACOS_TESTING"] != "true"
    #   testcase.skip(
    #     "Profiling is not supported on macOS. If you still want to run these specs, you can use " \
    #     "DD_PROFILING_MACOS_TESTING=true to override this check."
    #   )
    # end

    return if Datadog::Profiling.supported?

    # Ensure profiling was loaded correctly
    raise "Profiling does not seem to be available: #{Datadog::Profiling.unsupported_reason}. " \
      "Try running `bundle exec rake compile` before running this test."
  end

  def decode_profile(encoded_profile)
    ::Perftools::Profiles::Profile.decode(Zstd.decompress(encoded_profile._native_bytes))
  end

  def samples_from_pprof(encoded_profile)
    decoded_profile = decode_profile(encoded_profile)

    string_table = decoded_profile.string_table
    pretty_sample_types = decoded_profile.sample_type.map { |it| string_table[it.type].to_sym }

    decoded_profile.sample.map do |sample|
      Sample.new(
        sample.location_id.map { |location_id| decode_frame_from_pprof(decoded_profile, location_id) },
        pretty_sample_types.zip(sample.value).to_h,
        sample.label.map do |it|
          key = string_table[it.key].to_sym
          [key, ((it.num == 0) ? string_table[it.str] : ProfileHelpers.maybe_fix_label_range(key, it.num))]
        end.sort.to_h,
      ).freeze
    end
  end

  def decode_frame_from_pprof(decoded_profile, location_id)
    strings = decoded_profile.string_table
    location = decoded_profile.location.find { |loc| loc.id == location_id }
    raise "Unexpected: Multiple lines for location" unless location.line.size == 1

    line_entry = location.line.first
    function = decoded_profile.function.find { |func| func.id == line_entry.function_id }

    Frame.new(strings[function.name], strings[function.filename], line_entry.line).freeze
  end

  def object_id_from(thread_id)
    if thread_id != "GC"
      Integer(thread_id.match(/\d+ \((?<object_id>\d+)\)/)[:object_id])
    else
      -1
    end
  end

  def samples_for_thread(samples, thread, expected_size: nil)
    result = samples.select do |sample|
      thread_id = sample.labels[:"thread id"]
      thread_id && object_id_from(thread_id) == thread.object_id
    end

    if expected_size
      expect(result.size).to(be(expected_size), "Found unexpected sample count in result: #{result}")
    end

    result
  end

  def sample_for_thread(samples, thread)
    samples_for_thread(samples, thread, expected_size: 1).first
  end

  def self.maybe_fix_label_range(key, value)
    if [:"local root span id", :"span id"].include?(key) && value < 0
      # pprof labels are defined to be decoded as signed values BUT the backend explicitly interprets these as unsigned
      # 64-bit numbers so we can still use them for these ids without having to fall back to strings
      value + 2**64
    else
      value
    end
  end

  def skip_if_gvl_profiling_not_supported(testcase)
    if RUBY_VERSION < "3.2."
      testcase.skip "GVL profiling is only supported on Ruby >= 3.2"
    end
  end
end

RSpec.configure do |config|
  config.include ProfileHelpers
end

RSpec::Matchers.define :raise_native_error do |expected_class, expected_message = nil, expected_telemetry_message = nil, &block|
  unless expected_class.is_a?(Class) && expected_class <= Datadog::Core::Native::Error
    raise ArgumentError, "expected_class must be a subclass of Datadog::Core::Native::Error"
  end

  supports_block_expectations

  def describe_expected(value)
    if value.respond_to?(:description) && value.description
      value.description
    else
      value.inspect
    end
  end

  def match_expected?(expected, actual, attribute)
    return true if expected.nil?

    actual_description = actual.nil? ? "nil" : actual.inspect

    if expected.respond_to?(:matches?)
      result = expected.matches?(actual)
      unless result
        @failure_message ||= if expected.respond_to?(:failure_message)
          expected.failure_message
        else
          "expected native exception #{attribute} to match #{describe_expected(expected)}, but was #{actual_description}"
        end
      end
      result
    elsif expected.is_a?(Regexp)
      actual_string = if actual.is_a?(String)
        actual
      elsif actual.respond_to?(:to_str)
        actual.to_str
      end
      result = actual_string && expected.match?(actual_string)
      unless result
        @failure_message ||= "expected native exception #{attribute} to match #{expected.inspect}, but was #{actual_description}"
      end
      result
    else
      result = actual == expected
      unless result
        @failure_message ||= "expected native exception #{attribute} to equal #{expected.inspect}, but was #{actual_description}"
      end
      result
    end
  end

  match do |actual_proc|
    @failure_message = nil
    @actual_error = nil

    actual_proc.call
    false
  rescue Datadog::Core::Native::Error => e
    @actual_error = e

    unless e.is_a?(expected_class)
      @failure_message =
        "expected native exception of class #{expected_class}, but #{e.class} was raised"
      return false
    end

    message_matches = match_expected?(expected_message, e.message, "message")
    telemetry_matches = match_expected?(expected_telemetry_message, e.telemetry_message, "telemetry message")

    return false unless message_matches && telemetry_matches

    block&.call(e)

    true
  end

  failure_message do
    if @actual_error
      @failure_message ||
        "expected native exception of class #{expected_class} with message #{expected_message.inspect} " \
        "and telemetry message #{expected_telemetry_message.inspect}, but got #{@actual_error.class} " \
        "with message #{@actual_error.message.inspect} and telemetry message #{@actual_error.telemetry_message.inspect}"
    else
      "expected native exception of class #{expected_class} with message #{expected_message.inspect} " \
      "and telemetry message #{expected_telemetry_message.inspect}, but no exception was raised"
    end
  end
end
