module Datadog
  module Contrib
    # Contains methods helpful for tracing/annotating HTTP request libraries
    module HttpAnnotationHelper
      def service_name(hostname, configuration_options)
        configuration_options[:split_by_domain] ? hostname : configuration_options[:service_name]
      end
    end
  end
end
