require 'thread'

# We import all patchers for every module we support, but this is fine
# because patchers do not include any 3rd party module nor even our
# patching code, which is required on demand, when patching.
require 'ddtrace/contrib/active_record/patcher'
require 'ddtrace/contrib/elasticsearch/patcher'
require 'ddtrace/contrib/http/patcher'
require 'ddtrace/contrib/redis/patcher'


module Datadog
  # Monkey is used for monkey-patching 3rd party libs.
  module Monkey
    @patched = []
    @autopatch_modules = { elasticsearch: true, http: true, redis: true, active_record: false }
    # Patchers should expose 2 methods:
    # - patch, which applies our patch if needed. Should be idempotent,
    #   can be call twice but should just do nothing the second time.
    # - patched?, which returns true if the module has been succesfully
    #   patched (patching might have failed if requirements were not here)
    @patchers = { elasticsearch: Datadog::Contrib::Elasticsearch::Patcher,
                  http: Datadog::Contrib::HTTP::Patcher,
                  redis: Datadog::Contrib::Redis::Patcher,
                  active_record: Datadog::Contrib::ActiveRecord::Patcher }
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
        patcher = @patchers[m]
        raise 'Unsupported module #{m}' unless patcher
        patcher.patch
      end
    end

    def patch(modules)
      modules.each do |k, v|
        patch_module(k) if v
      end
    end

    def get_patched_modules
      patched = autopatch_modules
      @patchers.each do |k, v|
        @mutex.synchronize do
          if v
            patcher = @patchers[k]
            patched[k] = patcher.patched? if patcher
          end
        end
      end
      patched
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
  end
end
