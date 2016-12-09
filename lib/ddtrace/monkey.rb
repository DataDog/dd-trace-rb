require 'ddtrace/contrib/elasticsearch/patch'
require 'ddtrace/contrib/redis/patch'

module Datadog
  # Monkey is used for monkey-patching 3rd party libs.
  module Monkey
    @patched = []

    module_function

    def autopatch_modules
      %w(elasticsearch redis).sort
    end

    def patch_all
      patch autopatch_modules
    end

    def patch_module(m)
      case m
      when 'elasticsearch'
        Datadog::Contrib::Elasticsearch::Patch.patch
      when 'redis'
        Datadog::Contrib::Redis::Patch.patch
      end
    end

    def patch(modules)
      modules.each do |m|
        patch_module(m)
      end
    end

    def get_patched_modules
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
