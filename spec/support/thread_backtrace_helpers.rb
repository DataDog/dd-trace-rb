# frozen_string_literal: true

# Module to test stack trace generation. Inspired by:
# https://github.com/ruby/ruby/blob/master/spec/ruby/core/thread/backtrace/location/fixtures/classes.rb
module ThreadBacktraceHelper
  def self.locations
    caller_locations
  end

  # Deeply nested blocks to test max_depth and max_depth_top_percentage variables
  def self.locations_inside_nested_blocks
    first_level_location = nil
    second_level_location = nil
    third_level_location = nil
    fourth_level_location = nil
    fifth_level_location = nil

    # rubocop:disable Lint/UselessTimes
    1.times do
      first_level_location = locations.first
      1.times do
        second_level_location = locations.first
        1.times do
          third_level_location = locations.first
          1.times do
            fourth_level_location = locations.first
            1.times do
              fifth_level_location = locations.first
            end
          end
        end
      end
    end
    # rubocop:enable Lint/UselessTimes

    [first_level_location, second_level_location, third_level_location, fourth_level_location, fifth_level_location]
  end

  def self.thousand_locations
    locations = []
    1000.times do
      locations << self.locations.first
    end
    locations
  end

  LocationASCII8Bit = Struct.new(:text, :path, :lineno, :label, keyword_init: true) do
    def to_s
      text
    end
  end

  def self.location_ascii_8bit
    location = locations.first
    LocationASCII8Bit.new(
      text: location.to_s.encode('ASCII-8BIT'),
      path: (location.absolute_path || location.path).encode('ASCII-8BIT'),
      lineno: location.lineno,
      label: location.label.encode('ASCII-8BIT')
    )

    [location]
  end
end
