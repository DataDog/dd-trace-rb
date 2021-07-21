require 'pathname'

module Datadog
  module Security
    # Helper methods to get vendored assets
    module Assets
      module_function

      def waf_rules
        @waf_rules ||= read('waf_rules.json')
      end

      def blocked
        @blocked ||= read('blocked.html')
      end

      def path
        Pathname.new(dir).join('assets')
      end

      def filepath(filename)
        path.join(filename)
      end

      def read(filename, mode = 'rb')
        File.open(filepath(filename), mode) { |f| f.read || raise('Unexpected nil IO object') }
      end

      def dir
        __dir__ || raise('Unexpected file eval')
      end
    end
  end
end
