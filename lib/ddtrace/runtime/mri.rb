module Datadog
  module Runtime
    # Interface to the native extension for the MRI runtime.
    module MRI
      def self.report_gc(&callback)
        GC.hook = callback
      end
    end
  end
end

begin
  require 'ddtrace/ddtrace'
rescue LoadError => e
  Datadog::Tracer.log.error("Unable to load MRI native extension: #{e}")
end
