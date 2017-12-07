require 'thread'

# We import all patchers for every module we support, but this is fine
# because patchers do not include any 3rd party module nor even our
# patching code, which is required on demand, when patching.
require 'ddtrace/contrib/base'
require 'ddtrace/contrib/rails/patcher'
require 'ddtrace/contrib/active_record/patcher'
require 'ddtrace/contrib/elasticsearch/patcher'
require 'ddtrace/contrib/faraday/patcher'
require 'ddtrace/contrib/grape/patcher'
require 'ddtrace/contrib/redis/patcher'
require 'ddtrace/contrib/http/patcher'
require 'ddtrace/contrib/aws/patcher'
require 'ddtrace/contrib/sucker_punch/patcher'
require 'ddtrace/contrib/mongodb/patcher'
require 'ddtrace/contrib/dalli/patcher'
require 'ddtrace/contrib/resque/patcher'
require 'ddtrace/contrib/racecar/patcher'

module Datadog
  # Monkey is used for monkey-patching 3rd party libs.
  module Monkey
    # Patchers should expose 2 methods:
    # - patch, which applies our patch if needed. Should be idempotent,
    #   can be call twice but should just do nothing the second time.
    # - patched?, which returns true if the module has been succesfully
    #   patched (patching might have failed if requirements were not here)

    @mutex = Mutex.new
    @registry = Datadog.registry

    module_function

    attr_accessor :registry

    def autopatch_modules
      registry.to_h
    end

    def patch_all
      patch(autopatch_modules)
    end

    def patch_module(m)
      @mutex.synchronize do
        patcher = registry[m]
        raise "Unsupported module #{m}" unless patcher
        patcher.patch if patcher.respond_to?(:patch)
      end
    end

    def patch(modules)
      modules.each do |k, v|
        patch_module(k) if v
      end
    end

    def get_patched_modules
      @mutex.synchronize do
        registry.each_with_object({}) do |entry, patched|
          next unless entry.klass.respond_to?(:patched?)
          patched[entry.name] = entry.klass.patched?
        end
      end
    end

    def without_warnings
      # This is typically used when monkey patching functions such as
      # intialize, which Ruby advices you not to. Use cautiously.
      v = $VERBOSE
      $VERBOSE = nil
      begin
        yield
      ensure
        $VERBOSE = v
      end
    end

    class << self
      attr_accessor :registry
    end
  end
end

Datadog::Monkey.patch_module(:rails)
