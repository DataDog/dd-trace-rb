# frozen_string_literal: true

require "json"
require "socket"

require_relative "../core/utils/time"
require_relative "../tracing/contrib/aws_lambda_ric/lifecycle"

module Datadog
  module Lambda
    # Sends Lambda custom distribution metrics without requiring dogstatsd-ruby.
    module Metrics
      HOST = "127.0.0.1"
      PORT = 8125

      @mutex = Mutex.new
      @socket = nil

      class << self
        def distribution(name, value, time: nil, tags: {})
          tag_list = tags.map { |key, tag_value| "#{key}:#{tag_value}" }
          tag_list.unshift("dd_lambda_layer:datadog-ruby#{ruby_version_tag}")

          if extension_running?
            send_to_extension(name, value, tag_list)
          else
            timestamp = (time || Core::Utils::Time.now).to_i
            $stdout.puts(JSON.generate(e: timestamp, m: name, t: tag_list, v: value))
            true
          end
        rescue => e
          Datadog.logger.warn("Error sending a Lambda custom metric: #{e.class}: #{e.message}")
          false
        end

        def close
          @mutex.synchronize do
            @socket&.close
            @socket = nil
          end
        end

        private

        def extension_running?
          Tracing::Contrib::AwsLambdaRic::Lifecycle.extension_running?
        end

        def send_to_extension(name, value, tags)
          metric = "#{name}:#{value}|d"
          metric = "#{metric}|##{tags.join(",")}" unless tags.empty?

          @mutex.synchronize do
            @socket ||= UDPSocket.new
            @socket.send(metric, 0, HOST, PORT)
          end
          true
        end

        def ruby_version_tag
          RUBY_VERSION.split(".").first(2).join
        end
      end
    end
  end
end

at_exit { Datadog::Lambda::Metrics.close }
