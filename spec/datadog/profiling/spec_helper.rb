require 'datadog/profiling'
if Datadog::Profiling.supported?
  require 'datadog/profiling/pprof/pprof_pb'
  require 'extlz4'
end

module ProfileHelpers
  Sample = Struct.new(:locations, :values, :labels) # rubocop:disable Lint/StructNewOverride
  Frame = Struct.new(:base_label, :path, :lineno)

  def skip_if_profiling_not_supported(testcase)
    testcase.skip('Profiling is not supported on JRuby') if PlatformHelpers.jruby?
    testcase.skip('Profiling is not supported on TruffleRuby') if PlatformHelpers.truffleruby?
    testcase.skip('Profiling is not supported on Ruby 2.1/2.2') if RUBY_VERSION.start_with?('2.1.', '2.2.')

    # Profiling is not officially supported on macOS due to missing libdatadog binaries,
    # but it's still useful to allow it to be enabled for development.
    if PlatformHelpers.mac? && ENV['DD_PROFILING_MACOS_TESTING'] != 'true'
      testcase.skip(
        'Profiling is not supported on macOS. If you still want to run these specs, you can use ' \
        'DD_PROFILING_MACOS_TESTING=true to override this check.'
      )
    end

    return if Datadog::Profiling.supported?

    # Ensure profiling was loaded correctly
    raise "Profiling does not seem to be available: #{Datadog::Profiling.unsupported_reason}. " \
      'Try running `bundle exec rake compile` before running this test.'
  end

  def decode_profile(pprof_data)
    ::Perftools::Profiles::Profile.decode(LZ4.decode(pprof_data))
  end

  def samples_from_pprof(pprof_data)
    decoded_profile = decode_profile(pprof_data)

    string_table = decoded_profile.string_table
    pretty_sample_types = decoded_profile.sample_type.map { |it| string_table[it.type].to_sym }

    decoded_profile.sample.map do |sample|
      Sample.new(
        sample.location_id.map { |location_id| decode_frame_from_pprof(decoded_profile, location_id) },
        pretty_sample_types.zip(sample.value).to_h,
        sample.label.map do |it|
          [
            string_table[it.key].to_sym,
            it.num == 0 ? string_table[it.str] : it.num,
          ]
        end.to_h,
      ).freeze
    end
  end

  def decode_frame_from_pprof(decoded_profile, location_id)
    strings = decoded_profile.string_table
    location = decoded_profile.location.find { |loc| loc.id == location_id }
    raise 'Unexpected: Multiple lines for location' unless location.line.size == 1

    line_entry = location.line.first
    function = decoded_profile.function.find { |func| func.id == line_entry.function_id }

    Frame.new(strings[function.name], strings[function.filename], line_entry.line).freeze
  end

  def object_id_from(thread_id)
    Integer(thread_id.match(/\d+ \((?<object_id>\d+)\)/)[:object_id])
  end

  def samples_for_thread(samples, thread)
    samples.select do |sample|
      thread_id = sample.labels[:'thread id']
      thread_id && object_id_from(thread_id) == thread.object_id
    end
  end

  # We disable heap_sample collection by default in tests since it requires some extra mocking/
  # setup for it to properly work.
  def build_stack_recorder(heap_samples_enabled: false)
    Datadog::Profiling::StackRecorder.new(
      cpu_time_enabled: true,
      alloc_samples_enabled: true,
      heap_samples_enabled: heap_samples_enabled
    )
  end
end

RSpec.configure do |config|
  config.include ProfileHelpers
end
