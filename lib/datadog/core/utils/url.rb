# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Helpers class that provides methods to proces URLs
      # such as filtering sensitive information.
      module Url
        def self.filter_sensitive_info(url)
          return nil if url.nil?

          url.gsub(%r{((https?|ssh)://)[^/]*@}, '\1')
        end
      end
    end
  end
end
