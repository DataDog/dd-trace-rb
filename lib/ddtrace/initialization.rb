module Datadog
  # Responsible for the behavior the tracer after it's completely
  # loaded, but before `require 'ddtrace'` returns control to
  # the user.
  class Initialization

    # @param tracer [Datadog] an application-level Datadog APM tracer object
    def initialize(tracer)
      @tracer = tracer
    end

    # Initializes the tracer.
    #
    # This performs performs any initialization necessary
    # before control is returned to the host application.
    #
    # The tracer should be ready for use after this call.
    #
    # This method is invoked once per application life cycle.
    def initialize!
      start_life_cycle

      # DEV: Code responsible for displaying a deprecation warning for a
      # deprecated version of Ruby.
      #
      # ruby_deprecation_warning
    end

    # Ensures tracer public API is ready for use.
    #
    # We want to eager load tracer components, as
    # this allows us to have predictable initialization of
    # inter-dependent parts.
    # It also allows the remove of concurrency primitives
    # from public tracer components, as they are guaranteed
    # to be a good state immediately.
    def start_life_cycle
      @tracer.send(:start!)
    end

    # DEV: Code responsible for displaying a deprecation warning for a
    # deprecated version of Ruby.
    #
    ## Ruby version deprecation warning, emitted once per application
    ## life cycle.
    ##
    ## Subcomponents can still emit their own deprecation warnings
    ## when needed.
    # def ruby_deprecation_warning
    #   if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1')
    #     @tracer.logger.warn(
    #       "Support for Ruby versions < 2.1 in dd-trace-rb is DEPRECATED.\n" \
    #       "Last version to support Ruby < 2.1 will be 0.49.x, which will only receive critical bugfixes.\n" \
    #       'Support for Ruby versions < 2.1 will be REMOVED in version 0.50.0.'
    #     )
    #   end
    # end
  end
end
