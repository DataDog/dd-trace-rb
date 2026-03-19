# frozen_string_literal: true

require_relative '../../core/ddsketch'
require_relative 'ext'
require_relative 'span_eligibility'
require_relative 'key_builder'

module Datadog
  module Tracing
    module Stats
      # The stats concentrator aggregates span metrics into time buckets.
      #
      # Each bucket covers a 10-second window. Spans are assigned to buckets
      # based on their end time (start + duration). Within each bucket, spans
      # are grouped by their 12-dimension aggregation key.
      #
      # For each group, the concentrator tracks:
      # - hits: total count of spans
      # - errors: count of error spans
      # - duration: total duration in nanoseconds
      # - top_level_hits: count of top-level spans
      # - ok_distribution: DDSketch of non-error span durations
      # - error_distribution: DDSketch of error span durations
      class Concentrator
        attr_reader :buckets

        # @param agent_peer_tags [Array<String>, nil] peer tag keys from agent /info
        def initialize(agent_peer_tags: nil)
          @buckets = {}
          @mutex = Mutex.new
          @agent_peer_tags = agent_peer_tags
        end

        # Set peer tags discovered from agent /info endpoint
        # @param tags [Array<String>, nil]
        def agent_peer_tags=(tags)
          @mutex.synchronize { @agent_peer_tags = tags }
        end

        # Add a finished span to the concentrator.
        #
        # @param span [Datadog::Tracing::Span] the finished span
        # @param synthetics [Boolean] whether the trace is from Synthetics
        # @param partial [Boolean] whether this is a partial flush snapshot
        def add_span(span, synthetics: false, partial: false)
          return unless SpanEligibility.eligible?(span, partial: partial)

          agent_peer_tags = nil
          @mutex.synchronize do
            agent_peer_tags = @agent_peer_tags
          end

          key = KeyBuilder.build(span, synthetics: synthetics, agent_peer_tags: agent_peer_tags)
          bucket_time = compute_bucket_time(span)
          duration_ns = span_duration_ns(span)
          is_error = span.status == Metadata::Ext::Errors::STATUS
          is_top_level = SpanEligibility.top_level?(span)

          @mutex.synchronize do
            bucket = @buckets[bucket_time] ||= {}
            group = bucket[key] ||= new_group

            group[:hits] += 1
            group[:errors] += 1 if is_error
            group[:duration] += duration_ns
            group[:top_level_hits] += 1 if is_top_level

            if is_error
              group[:error_distribution].add(duration_ns.to_f)
            else
              group[:ok_distribution].add(duration_ns.to_f)
            end
          end
        end

        # Flush all completed buckets.
        #
        # A bucket is considered complete if its time window has elapsed.
        # On shutdown, pass `force: true` to flush all buckets including the current one.
        #
        # @param now_ns [Integer] current time in nanoseconds
        # @param force [Boolean] if true, flush all buckets (used on shutdown)
        # @return [Hash] map of bucket_time => { key => group_stats }
        def flush(now_ns:, force: false)
          @mutex.synchronize do
            flushed = {}
            cutoff = force ? Float::INFINITY : now_ns

            keys_to_delete = []
            @buckets.each do |bucket_time, groups|
              bucket_end = bucket_time + Ext::BUCKET_DURATION_NS
              if bucket_end <= cutoff || force
                flushed[bucket_time] = groups
                keys_to_delete << bucket_time
              end
            end

            keys_to_delete.each { |k| @buckets.delete(k) }

            flushed
          end
        end

        private

        # Compute the aligned bucket time for a span based on its end time.
        #
        # @param span [Datadog::Tracing::Span]
        # @return [Integer] bucket start time in nanoseconds
        def compute_bucket_time(span)
          end_time_ns = span_end_time_ns(span)
          end_time_ns - (end_time_ns % Ext::BUCKET_DURATION_NS)
        end

        # @param span [Datadog::Tracing::Span]
        # @return [Integer] span end time in nanoseconds
        def span_end_time_ns(span)
          return 0 unless span.end_time

          (span.end_time.to_f * 1e9).to_i
        end

        # @param span [Datadog::Tracing::Span]
        # @return [Integer] span duration in nanoseconds
        def span_duration_ns(span)
          duration = span.duration
          return 0 unless duration

          (duration * 1e9).to_i
        end

        # Create a new stats group with zeroed counters and fresh sketches.
        # @return [Hash]
        def new_group
          {
            hits: 0,
            errors: 0,
            duration: 0,
            top_level_hits: 0,
            ok_distribution: Core::DDSketch.new,
            error_distribution: Core::DDSketch.new,
          }
        end
      end
    end
  end
end
