# frozen_string_literal: true

require "pathname"

module Datadog
  module AppSec
    # Helper methods to get vendored assets
    module Assets
      def self.waf_rules(kind = :recommended)
        read("waf_rules/#{kind}.json")
      end

      def self.waf_processors
        read("waf_rules/processors.json")
      end

      def self.waf_scanners
        read("waf_rules/scanners.json")
      end

      def self.blocked(format: :html)
        (@blocked ||= {})[format] ||= read("blocked.#{format}").freeze
      end

      def self.path
        Pathname.new(dir).join("assets")
      end

      def self.filepath(filename)
        path.join(filename)
      end

      def self.read(filename, mode = "rb")
        File.open(filepath(filename), mode) { |f| f.read || raise("Unexpected nil IO object") }
      end

      def self.dir
        # Happens only if this file is evaluated standalone, which should not happen
        # Necessary to make type-checker happy with a non-nilable return value
        __dir__ || raise("Unexpected file eval")
      end
    end
  end
end
