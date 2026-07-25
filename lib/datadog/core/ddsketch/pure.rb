# frozen_string_literal: true

module Datadog
  module Core
    class DDSketch
      # Pure-Ruby implementation of DDSketch, used when the native `libdatadog_api`
      # extension is unavailable (e.g. JRuby, TruffleRuby), so Data Streams Monitoring
      # can run on those platforms.
      #
      # This is a faithful port of libdatadog's minimal DDSketch
      # (see libdatadog `libdd-ddsketch/src/lib.rs`, which the native extension binds to):
      # a logarithmic index mapping over a low-collapsing dense store, supporting only
      # positive and zero values. `#encode` uses the same wire format and mapping
      # parameters as the native implementation, so the Datadog agent and backend decode
      # it and merge it with native-produced sketches within DDSketch's relative-accuracy
      # guarantee.
      #
      # @see Datadog::Core::DDSketch.build
      class Pure
        # Relative accuracy guaranteed by the mapping (1/129). Matches libdatadog's
        # `DDSketch::default`, which is the grid the Datadog backend expects.
        RELATIVE_ACCURACY = 0.007751937984496124

        # Base of the exponential bin sizing, gamma = (1 + a) / (1 - a) = 65/64 = 1.015625.
        GAMMA = (1.0 + RELATIVE_ACCURACY) / (1.0 - RELATIVE_ACCURACY)

        # Converts a natural log to a base-gamma log: log_gamma(v) = ln(v) * MULTIPLIER.
        MULTIPLIER = 1.0 / Math.log(GAMMA)

        # Smallest value the Datadog backend keeps a dedicated sketch bin for; used to
        # derive the index offset so bin indexes stay positive over the useful range.
        BACKEND_SKETCH_MIN_VALUE = 1e-9

        # Offset applied to every bin index (1338.5), matching libdatadog's default so the
        # serialized mapping is identical to the native sketch.
        INDEX_OFFSET = (1.0 - (Math.log(BACKEND_SKETCH_MIN_VALUE) / Math.log(GAMMA)).floor) + 0.5

        # Values below this map to the zero bucket rather than a regular bin. Derived
        # exactly as libdatadog does, bounded so bin indexes never underflow a 32-bit int.
        MIN_INDEXABLE_VALUE = [
          Float::MIN * GAMMA,
          Math.exp((-2_147_483_648.0 - INDEX_OFFSET) / MULTIPLIER + 1.0),
        ].max

        # Maximum number of bins retained; the lowest bins are collapsed together once
        # this is exceeded (low-collapsing dense store), matching libdatadog's default.
        MAX_BINS = 2048

        def initialize
          reset
        end

        # Add a single point to the sketch.
        # @param point [::Numeric] the value to add; must be non-negative and finite
        # @return [self]
        def add(point)
          point = point.to_f
          raise "DDSketch add failed: point is invalid" if invalid_point?(point)

          insert(point, 1.0)
          self
        end

        # Add a point with an explicit count/weight to the sketch.
        # @param point [::Numeric] the value to add; must be non-negative and finite
        # @param count [::Numeric] the weight for this point; must be finite
        # @return [self]
        def add_with_count(point, count)
          point = point.to_f
          count = count.to_f
          raise "DDSketch add_with_count failed: count is invalid" if count.nan? || count.infinite?
          raise "DDSketch add_with_count failed: point is invalid" if invalid_point?(point)

          insert(point, count)
          self
        end

        # @return [::Float] the total weight of all points in the sketch
        def count
          @zero_count + @bins.sum(0.0)
        end

        # Serialize the sketch to the DDSketch protobuf wire format and reset it for reuse.
        # The reset matches the native extension, whose encode consumes the sketch.
        # @return [::String] the encoded sketch as a binary string
        def encode
          bytes = serialize
          reset
          bytes
        end

        private

        def reset
          @bins = []      # : Array[Float] -- contiguous bin weights starting at @bin_offset
          @bin_offset = 0 # : Integer -- bin index of @bins[0]
          @zero_count = 0.0
        end

        def invalid_point?(point)
          point < 0.0 || point.nan? || point.infinite?
        end

        def insert(point, count)
          if point < MIN_INDEXABLE_VALUE
            @zero_count += count
          else
            store_index = bin_index_to_store_index(index(point))
            @bins[store_index] += count
          end
        end

        # Mirror libdatadog's exact order of operations (do not reorder) so indexes
        # match the native implementation.
        def index(value)
          (Math.log(value) * MULTIPLIER + INDEX_OFFSET).floor
        end

        # Map a bin index into a slot in @bins, growing/collapsing the dense store as needed.
        def bin_index_to_store_index(bin_index)
          if @bins.empty?
            @bin_offset = bin_index
            @bins.push(0.0)
            return 0
          end

          if bin_index < @bin_offset
            # Extend downward, capped by remaining capacity; anything beyond capacity
            # collapses into the lowest stored bin (slot 0).
            additional = [@bin_offset - bin_index, MAX_BINS - @bins.length].min
            additional = 0 if additional < 0
            @bins = Array.new(additional, 0.0).concat(@bins)
            @bin_offset -= additional
            0
          elsif @bin_offset + @bins.length <= bin_index
            bin_range_size = bin_index - @bin_offset + 1
            collapse_low_bins(bin_range_size - MAX_BINS) if bin_range_size > MAX_BINS
            # Recompute after a possible collapse shifted @bin_offset.
            store_index = bin_index - @bin_offset
            (store_index - @bins.length + 1).times { @bins.push(0.0) }
            store_index
          else
            bin_index - @bin_offset
          end
        end

        # Collapse (sum) the lowest `bin_number` bins into the new lowest bin.
        def collapse_low_bins(bin_number)
          removed = @bins.shift(bin_number).sum(0.0)
          if @bins.empty?
            @bins.unshift(removed)
          else
            @bins[0] += removed
          end
          @bin_offset += bin_number
        end

        # Hand-rolled DDSketch protobuf encoder (google-protobuf is a test-only dependency).
        # Field order and proto3 default-omission follow prost so the bytes match the
        # native extension exactly.
        def serialize
          out = "".b

          # field 1: mapping (IndexMapping)
          mapping = "".b
          mapping << 0x09 << [GAMMA].pack("E")                          # gamma (double)
          mapping << 0x11 << [INDEX_OFFSET].pack("E") unless INDEX_OFFSET == 0.0 # index_offset (double)
          # interpolation is NONE (0) and omitted by proto3 default rules
          out << 0x0A << write_varint(mapping.bytesize) << mapping

          # field 2: positive_values (Store)
          positive = "".b
          unless @bins.empty?
            packed = @bins.pack("E*")                                   # contiguous_bin_counts (packed double)
            positive << 0x12 << write_varint(packed.bytesize) << packed
          end
          positive << 0x18 << write_zigzag32(@bin_offset) unless @bin_offset == 0 # contiguous_bin_index_offset (sint32)
          out << 0x12 << write_varint(positive.bytesize) << positive

          # field 3: negative_values (always present, always empty)
          out << 0x1A << write_varint(0)

          # field 4: zero_count (double), omitted when zero
          out << 0x21 << [@zero_count].pack("E") unless @zero_count == 0.0

          out
        end

        # Unsigned LEB128 varint.
        def write_varint(value)
          out = "".b
          loop do
            byte = value & 0x7F
            value >>= 7
            if value.zero?
              out << byte
              break
            else
              out << (byte | 0x80)
            end
          end
          out
        end

        # sint32 zigzag encoding followed by a varint (32-bit wraparound emulated).
        def write_zigzag32(value)
          write_varint(((value << 1) ^ (value >> 31)) & 0xFFFFFFFF)
        end
      end
    end
  end
end
