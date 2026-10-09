# frozen_string_literal: true

# An observed set of durations for one task or Gemfile. Knows its own
# percentiles, which become the weight entries in the manifest.
module TestBatching
  class Samples
    def initialize(values)
      @sorted = values.sort
    end

    def to_h
      {"p50_seconds" => p50.round(3), "p90_seconds" => p90.round(3), "samples" => size}
    end

    private

    def size
      @sorted.length
    end

    def p50
      middle = size / 2
      return @sorted[middle] if size.odd?

      (@sorted[middle - 1] + @sorted[middle]) / 2.0
    end

    def p90
      @sorted.fetch(((size - 1) * 0.9).ceil)
    end
  end
end
