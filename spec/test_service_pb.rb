if RUBY_VERSION < '2.3'
  require_relative 'datadog/tracing/contrib/grpc/support/gen/grpc-1.19.0/test_service_pb'
else
  require_relative 'datadog/tracing/contrib/grpc/support/gen/test_service_pb'
end
