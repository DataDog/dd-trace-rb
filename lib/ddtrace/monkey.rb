module Datadog
  # TODO: Remove me!
  # Monkey was used for monkey-patching 3rd party libs.
  # It is now DEPRECATED. This API is no-op, and serves only to warn
  # of its deactivation.
  module Monkey
    @registry = Datadog.registry

    DEPRECATION_WARNING = %(
      Datadog::Monkey has been REMOVED as of version 0.11.1.
      All calls to Datadog::Monkey are no-ops.
      *Implementations using Monkey will no longer function*.
      Upgrade to the new configuration API using the migration guide here:
      https://github.com/DataDog/dd-trace-rb/releases/tag/v0.11.0).freeze

    module_function

    def registry
      log_deprecation_warning('Monkey#registry')
      @registry
    end

    def autopatch_modules
      log_deprecation_warning('Monkey#autopatch_modules')
      {}
    end

    def patch_all
      log_deprecation_warning('Monkey#patch_all')
    end

    def patch_module(m)
      log_deprecation_warning('Monkey#patch_module')
    end

    def patch(modules)
      log_deprecation_warning('Monkey#patch')
    end

    def get_patched_modules
      log_deprecation_warning('Monkey#get_patched_modules')
      {}
    end

    def without_warnings(&block)
      log_deprecation_warning('Monkey#without_warnings')
      Datadog::Patcher.without_warnings(&block)
    end

    def log_deprecation_warning(method)
      Datadog.logger.warn("#{method}:#{DEPRECATION_WARNING}")
    end

    class << self
      attr_writer :registry
    end
  end
end
