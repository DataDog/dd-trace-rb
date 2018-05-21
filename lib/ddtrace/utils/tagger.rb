module Datadog
  module Utils
    # Helper module for tagging list of values
    module Tagger
      # Tag span based on whitelisted values converted from source map
      #
      # @param [Datadog::Span] request_span
      # @param [Array] whitelist
      # @param [Datadog::Utils::BaseTagConverter] converter
      # @param [Hash] source
      def self.tag(request_span, whitelist, converter, source)
        return if whitelist.nil?

        whitelist.each do |entry|
          tag_name = converter.name(entry)
          next unless request_span.get_tag(tag_name).nil?

          tag_value = converter.value(entry, source)
          request_span.set_tag(tag_name, tag_value) if tag_value
        end
      end
    end
  end
end
