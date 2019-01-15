module Datadog
  module Runtime
    # Retrieves number of threads from runtime
    module ThreadCount
      module_function

      def value
        Thread.list.count
      end

      def available?
        Thread.respond_to?(:list)
      end
    end
  end
end
