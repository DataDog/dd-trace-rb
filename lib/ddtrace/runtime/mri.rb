module Datadog
  module Runtime
    module MRI
    end
  end
end

begin
  require 'ddtrace/ddtrace'
rescue LoadError => e
  Datadog::Tracer.log.error("Unable to load MRI native extension: #{e}")
end
