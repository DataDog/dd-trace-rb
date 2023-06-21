#!/bin/bash

mkdir -p ./spec/datadog/tracing/contrib/grpc/support/gen/grpc-1.19.0

gem install grpc-tools -v 1.19.0

grpc_tools_ruby_protoc \
    -I ./spec/datadog/tracing/contrib/grpc/support/proto \
    --ruby_out=./spec/datadog/tracing/contrib/grpc/support/gen/grpc-1.19.0 \
    --grpc_out=./spec/datadog/tracing/contrib/grpc/support/gen/grpc-1.19.0 \
    ./spec/datadog/tracing/contrib/grpc/support/proto/test_service.proto

gem install grpc-tools

grpc_tools_ruby_protoc \
    -I ./spec/datadog/tracing/contrib/grpc/support/proto \
    --ruby_out=./spec/datadog/tracing/contrib/grpc/support/gen \
    --grpc_out=./spec/datadog/tracing/contrib/grpc/support/gen \
    ./spec/datadog/tracing/contrib/grpc/support/proto/test_service.proto
