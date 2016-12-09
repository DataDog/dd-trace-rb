require 'thread'
require 'ddtrace/contrib/elasticsearch/patch'
require 'ddtrace/contrib/redis/patch'

module Datadog
  # Monkey is used for monkey-patching 3rd party libs.
  module Monkey
    @patched = []
    @autopatch_modules = { elasticsearch: true, redis: true }
    @mutex = Mutex.new

    module_function

    def autopatch_modules
      @autopatch_modules.clone
    end

    def patch_all
      patch @autopatch_modules
    end

    def patch_module(m)
      @mutex.synchronize do
        case m
        when :elasticsearch
          Datadog::Contrib::Elasticsearch::Patch.patch
        when :redis
          Datadog::Contrib::Redis::Patch.patch
        else
          raise "Unsupported module '#{k}'"
        end
      end
    end

    def patch(modules)
      modules.each do |k, v|
        patch_module(k) if v
      end
    end

    def get_patched_modules
      patched = autopatch_modules
      autopatch_modules.each do |k, _|
        case k
        when :elasticsearch
          patched[k] = Datadog::Contrib::Elasticsearch::Patch.patched?
        when :redis
          patched[k] = Datadog::Contrib::Redis::Patch.patched?
        else
          raise "Unsupported module '#{k}'"
        end
      end
      patched
    end
  end
end
