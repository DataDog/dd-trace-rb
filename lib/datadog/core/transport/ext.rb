# frozen_string_literal: true

require_relative '../configuration/ext'
# DEV(2.0): This file should replace /ddtrace/transport/ext.rb
# WARN: This file is used in /dd trace/transport/ext.rb which is a public API. Any changes here
# should be treated as changes to a public API.
module Datadog
  module Core
    module Transport
      module Ext
        module HTTP
          ADAPTER = Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
          DEFAULT_HOST = Datadog::Core::Configuration::Ext::Agent::HTTP::DEFAULT_HOST
          DEFAULT_PORT = Datadog::Core::Configuration::Ext::Agent::HTTP::DEFAULT_PORT

          HEADER_CONTAINER_ID = 'Datadog-Container-ID'
          HEADER_DD_API_KEY = 'DD-API-KEY'
          # Tells agent that `_dd.top_level` metrics have been set by the tracer.
          # The agent will not calculate top-level spans but instead trust the tracer tagging.
          #
          # This prevents partially flushed traces being mistakenly marked as top-level.
          #
          # Setting this header to any non-empty value enables this feature.
          HEADER_CLIENT_COMPUTED_TOP_LEVEL = 'Datadog-Client-Computed-Top-Level'
          HEADER_META_LANG = 'Datadog-Meta-Lang'
          HEADER_META_LANG_VERSION = 'Datadog-Meta-Lang-Version'
          HEADER_META_LANG_INTERPRETER = 'Datadog-Meta-Lang-Interpreter'
          HEADER_META_TRACER_VERSION = 'Datadog-Meta-Tracer-Version'

          # Header that prevents the Net::HTTP integration from tracing internal trace requests.
          # Set it to any value to skip tracing.
          HEADER_DD_INTERNAL_UNTRACED_REQUEST = 'DD-Internal-Untraced-Request'
        end

        module Test
          ADAPTER = :test
        end

        module UnixSocket
          ADAPTER = Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
          DEFAULT_PATH = Datadog::Core::Configuration::Ext::Agent::UnixSocket::DEFAULT_PATH
          DEFAULT_TIMEOUT_SECONDS = Datadog::Core::Configuration::Ext::Agent::UnixSocket::DEFAULT_TIMEOUT_SECONDS
        end
      end
    end
  end
end
