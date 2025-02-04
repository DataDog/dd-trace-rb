# frozen_string_literal: true

require 'libdatadog'
require_relative '../transport/traces'

module Datadog
  module Tracing
    module Transport
      # This module contains the classes defined in the libdatadog-api/data-pipeline extension
      module TraceExporter
        # A TraceExporter client used to send traces to the agent through the trace exporter
        class Client
          # Initialize a client based on the provided TraceExporter::Config
          def initialize(config)
            _native_initialize(config)
          end

          def send
            _native_send
          end
        end

        # A config used to initialize a TraceExporter::Client
        class Config
          def set_url(url)
            _native_set_url(url)
          end

          def set_tracer_version(version)
            _native_set_tracer_version(version)
          end

          def set_language(lang)
            _native_set_language(lang)
          end

          def set_lang_version(lang_version)
            _native_set_lang_version(lang_version)
          end

          def set_lang_interpreter(lang_interpreter)
            _native_set_lang_interpreter(lang_interpreter)
          end

          # Set the hostname
          def set_hostname(hostname)
            _native_set_hostname(hostname)
          end

          # Set the env
          def set_env(env)
            _native_set_env(env)
          end

          # Set the version of the app
          def set_version(version)
            _native_set_version(version)
          end

          # Set the default service of the tracer
          def set_service(service)
            _native_set_service(service)
          end
        end

        # Needs to answer to
        # service_rates => Returned by callback by libdatadog, probably have to be faked into an array.
        #                  Used by writer_update_priority_sampler_rates_callback
        # trace_count => simply the value sent to the trace_exporter doesn't come from the agent response
        #                Actually to support multiple service names we need to return the full service_rates object
        #
        # internal_error? => used by the update_priority_sampler function
        module Traces
          class Response
            include Transport::Traces::Response
          end

          # transport
          class Transport
            # Dummy stats for tests
            attr_reader :stats

            def initialize
              config = Transport::TraceExporter::Config.new
              config.set_git_commit_sha(Datadog::Core::Environment::Git.git_commit_sha)
              @exporter = Transport::TraceExporter::Exporter.new(config)
              @stats = Transport::Statistics.stats
            end

            def send_traces(traces)
              encoder = Core::Encoding::MsgpackEncoder
              chunker = Datadog::Tracing::Transport::Traces::Chunker.new(encoder)
              responses = chunker.encode_in_chunks(traces.lazy).map do |encoded_traces, trace_count|
                exporter.send(encoded_traces, trace_count)
                Response
              end

              # Force resolution of lazy enumerator.
              #
              # The "correct" method to call here would be `#force`,
              # as this method was created to force the eager loading
              # of a lazy enumerator.
              #
              # Unfortunately, JRuby < 9.2.9.0 erroneously eagerly loads
              # the lazy Enumerator during intermediate steps.
              # This forces us to use `#to_a`, as this method works for both
              # lazy and regular Enumerators.
              # Using `#to_a` can mask the fact that we expect a lazy
              # Enumerator.
              responses.to_a
            end
          end
        end
      end
    end
  end
end
