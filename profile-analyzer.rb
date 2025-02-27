require_relative "spec/datadog/profiling/pprof/pprof_pb"
require "extlz4"
require "pry"
require "set"

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
end

include ProfileHelpers

class Analyzer
  def initialize(decoded_profile)
    @decoded_profile = decoded_profile
  end

  def decode_location(decoded_profile = @decoded_profile, location)
    line_entry = location&.line&.first
    function = line_entry ? decoded_profile.function.find { |func| func.id == line_entry.function_id } : nil

    function ? [decoded_profile.string_table[function.name], decoded_profile.string_table[function.filename], [location.id, function.id]] : [location_id]
  end

  def locations_to_string_ids(decoded_profile = @decoded_profile, sample)
    sample.location_id.map do |location_id|
      location = decoded_profile.location.find { |loc| loc.id == location_id }
      line_entry = location&.line&.first
      function = line_entry ? decoded_profile.function.find { |func| func.id == line_entry.function_id } : nil

      function ? [decoded_profile.string_table[function.name], decoded_profile.string_table[function.filename], [location_id, function.id]] : [location_id]
    end
  end

  def sample_labels(decoded_profile = @decoded_profile, sample)
    string_table = decoded_profile.string_table

    sample.label.map do |it|
      key = string_table[it.key].to_sym
      [key, ((it.num == 0) ? string_table[it.str] : ProfileHelpers.maybe_fix_label_range(key, it.num))]
    end.sort.to_h
  end

  def self.analyze(path, decompress: true)
    invalid_pprof = File.read(path)
    decoded_profile = decompress ? decode_profile(invalid_pprof) : ::Perftools::Profiles::Profile.decode(invalid_pprof)

    Analyzer.new(decoded_profile).call
  end

  def call(decoded_profile = @decoded_profile)
    samples_without_timeline = decoded_profile.sample.select { |s| s.label.any? { |l| l.key == 3 } }

    puts "#{decoded_profile.location.size} locations found"
    puts "Sample types are #{decoded_profile.sample_type.map { |it| "#{decoded_profile.string_table[it.type]}/#{decoded_profile.string_table[it.unit]}" }}"

    last_location_id = decoded_profile.location.last.id
    all_broken = decoded_profile.sample.select { |s| s.location_id.any? { |id| id > last_location_id || id == 0 } }

    puts "There are #{all_broken.size} broken samples in this profile"

    binding.pry

    replayed = Replayer.new(decoded_profile).replay
    File.write("replayed_profile_v3.pprof", replayed)

    binding.pry
  end
end

class Replayer
  attr_accessor :decoded_profile

  def initialize(decoded_profile)
    @decoded_profile = decoded_profile
    require 'datadog'
  end

  def replay
    sample_types = decoded_profile.sample_type.map { |it| [decoded_profile.string_table[it.type], decoded_profile.string_table[it.unit]] }
    # string_table = decoded_profile.string_table.to_a
    locations = [nil, *decoded_profile.location.map { |loc| line = loc.line.first; [line.function_id, line.line] }]
    functions = [nil, *decoded_profile.function.map { |it| [decoded_profile.string_table[it.name], decoded_profile.string_table[it.filename]] }]
    samples = decoded_profile.sample.map { |it| [it.location_id.to_a, it.value.to_a, it.label.map { |l| [decoded_profile.string_table[l.key], l.str == 0 ? nil : decoded_profile.string_table[l.str], l.num] }] }

    # To hit the exact same ordering as the original profile, we need to take into account that all samples with timestamps are serialized
    # before all samples without timestamps, but that's not the order they were registered into libdatadog.
    reordered_samples = reorder(samples)

    binding.pry

    Datadog::Profiling::NativeExtension::Testing._native_replay(sample_types, locations, functions, reordered_samples)
  end

  def compare_samples(s1, s2)
    res = s1.first.max <=> s2.first.max

    if res != 0
      res
    else
      the_max = s1.first.max
      l1 = Set.new(s1.first)
      l2 = Set.new(s2.first)

      res = 0
      decider_included = false

      while the_max > 0
        the_max -= 1

        if l1.include?(the_max) && l2.include?(the_max)

        else
          res = l1.include?(the_max) ? -1 : 1
          decider_included = l1.include?(the_max) || l2.include?(the_max)
          break
        end
      end

      # puts "Comparing #{l1} and #{l2}, result is #{res} (#{the_max} was the decider, included: #{decider_included})"

      res
    end
  end

  def reorder(samples)
    with_timestamp, without_timestamp = samples.partition { |s| s.last.any? { |label, _| label == 'end_timestamp_ns' } }
    without_timestamp.sort! do |s1, s2|
      compare_samples(s1, s2)
    end

    merged = []
    i = 0
    j = 0

    while i < with_timestamp.size && j < without_timestamp.size
      if compare_samples(with_timestamp[i], without_timestamp[j]) <= 0
        merged << with_timestamp[i]
        i += 1
      else
        merged << without_timestamp[j]
        j += 1
      end
    end

    while i < with_timestamp.size
      merged << with_timestamp[i]
      i += 1
    end

    while j < without_timestamp.size
      merged << without_timestamp[j]
      j += 1
    end

    binding.pry

    merged
  end
end

if ARGV.any?
  begin
    Analyzer.analyze(ARGV.first)
  rescue LZ4::Error
    Analyzer.analyze(ARGV.first, decompress: false)
  end
else
  binding.pry
end
