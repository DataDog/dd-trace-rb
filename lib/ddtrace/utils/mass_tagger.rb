module Datadog
  module Utils
    # Helper class to used to tag configured headers
    module MassTagger

      def self.tag(request_span, whitelist, tagger, source)
        return if whitelist.nil?

        whitelist.each do |header|
          tag_name = tagger.name(header)
          next unless request_span.get_tag(tag_name).nil?

          tag_value = tagger.value(header, source)
          request_span.set_tag(tag_name, tag_value) if tag_value
        end
      end
    end
  end
end
