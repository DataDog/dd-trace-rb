require 'ddtrace/contrib/elasticsearch/patch'
require 'ddtrace/contrib/redis/patch'

module Datadog
  module Contrib
    # Monkey is used for monkey-patching 3rd party libs.
    module Autopatch
      @patched = []

      module_function

      def autopatch_modules
        %w(elasticsearch redis).sort
      end

      def autopatch
        patch_modules autopatch_modules
      end

      def patch_modules(modules)
        modules.each do |m|
          case m
          when 'elasticsearch'
            Datadog::Contrib::Elasticsearch::Patch.patch
          when 'redis'
            Datadog::Contrib::Redis::Patch.patch
          end
        end
      end

      def patched_modules
        patched = []
        autopatch_modules.each do |m|
          case m
          when 'elasticsearch'
            patched << m if Datadog::Contrib::Elasticsearch::Patch.patched
          when 'redis'
            patched << m if Datadog::Contrib::Redis::Patch.patched
          end
        end
        m.sort
      end
    end
  end
end
