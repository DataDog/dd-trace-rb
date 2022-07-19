module Datadog
  module Tracing
    module Stats
      # TOP-LEVEL description
      class Repository
        attr_reader :data, :mutex

        def initialize
          @data = Hash.new do |hash, key|
            hash[key] = Hash.new { |nested_hash, k| nested_hash[k] = Stats.new }
          end
          @mutex = Mutex.new
        end

        def update!(k1, k2, span)
          mutex.synchronize do
            data[k1][k2].update!(span)
          end
        end

        def flush!
          mutex.synchronize do
            # TODO: serialize & send request
            @data.clear
          end
        end

        # TOP-LEVEL description
        class Stats
          attr_reader :hits, :top_level_hits, :duration, :errors, :err_distribution, :ok_distribution

          def initialize
            @hits = 0
            @top_level_hits = 0
            @duration = 0
            @errors = 0
            @err_distribution = DDSketch::LogCollapsingLowestDenseSketch.new(relative_accuracy: 0.00775, bin_limit: 2048)
            @ok_distribution  = DDSketch::LogCollapsingLowestDenseSketch.new(relative_accuracy: 0.00775, bin_limit: 2048)
          end

          def update!(span)
            @hits += 1
            @duration += span.duration_nano
            @top_level_hits += 1 if span.__send__(:service_entry?)

            if span.error?
              @errors += 1
              @err_distribution.add(span.duration_nano)
            else
              @ok_distribution.add(span.duration_nano)
            end
          end
        end
      end
    end
  end
end
