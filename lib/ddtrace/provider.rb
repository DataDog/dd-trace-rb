module DataDog
  # DefaultContextProvider is a default context provider that retrieves
  # all contexts from the current thread-local storage. It is suitable for
  # synchronous programming.
  class DefaultContextProvider
    def initialize
      @context = Datadog::ThreadLocalContext.new
    end

    def call
      @context.get()
    end
  end
end
