# frozen_string_literal: true

require_relative "../../core/workers/polling"
require_relative "../evaluation_engine"
require_relative "parser"
require_relative "transport"

module Datadog
  module OpenFeature
    module Agentless
      # Polls the agentless endpoint and applies accepted configuration.
      class ConfigurationSource
        MAX_ATTEMPTS = 3
        FIRST_RETRY_MIN_SECONDS = 2.0
        FIRST_RETRY_MAX_SECONDS = 10.0
        SECOND_RETRY_MIN_SECONDS = 5.0
        SECOND_RETRY_MAX_SECONDS = 30.0
        RETRY_JITTER = 0.2

        include Core::Workers::Polling

        attr_reader :etag

        def self.build(settings, endpoint:, apply:, logger: Datadog.logger)
          api_key = settings.api_key.to_s.strip
          if endpoint.managed? && api_key.empty?
            logger.warn("Feature Flags agentless delivery requires DD_API_KEY; agentless delivery is disabled")
            return
          end

          new(
            endpoint: endpoint,
            api_key: api_key.empty? ? nil : api_key,
            poll_interval_seconds: settings.open_feature.agentless_poll_interval_seconds,
            request_timeout_seconds: settings.open_feature.agentless_request_timeout_seconds,
            apply: apply,
            logger: logger,
          )
        end

        def initialize(
          endpoint:,
          api_key:,
          poll_interval_seconds:,
          request_timeout_seconds:,
          apply:,
          logger:,
          transport: nil,
          random: nil,
          retry_wait: nil
        )
          @transport = transport || Transport.new(
            endpoint: endpoint,
            api_key: api_key,
            timeout_seconds: request_timeout_seconds,
          )
          @apply = apply
          @logger = logger
          @poll_interval_seconds = poll_interval_seconds
          @random = random
          @retry_wait = retry_wait || method(:wait_for_retry)
          @etag = nil
          @warned = {}
          @lifecycle_mutex = Mutex.new
          @started = false
          @stopped = false

          self.enabled = true
          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_RESTART
          self.loop_base_interval = poll_interval_seconds
        end

        def start
          @lifecycle_mutex.synchronize do
            return false if @stopped
            return true if @started && !forked?

            perform
            @started = true
          end

          true
        end

        def stop
          @lifecycle_mutex.synchronize do
            return false if @stopped

            @stopped = true
            self.enabled = false
          end

          super(true)
          true
        end

        def perform
          poll
        end

        def poll
          attempt = 1

          while attempt <= MAX_ATTEMPTS
            return if stopped?

            response = @transport.get(@etag)
            unless retryable?(response)
              apply_response(response)
              return
            end

            if attempt == MAX_ATTEMPTS
              warn_failure(response, attempt)
              return
            end

            return if wait_before_retry(retry_delay(attempt))

            attempt += 1
          end
        end

        private

        def stopped?
          @lifecycle_mutex.synchronize { @stopped }
        end

        def retryable?(response)
          status = response.status
          return true unless status

          status == 408 || status == 429 || status.between?(500, 599)
        end

        def retry_delay(attempt)
          base = if attempt == 1
            clamp(@poll_interval_seconds / 6.0, FIRST_RETRY_MIN_SECONDS, FIRST_RETRY_MAX_SECONDS)
          else
            clamp(@poll_interval_seconds / 3.0, SECOND_RETRY_MIN_SECONDS, SECOND_RETRY_MAX_SECONDS)
          end
          random = @random ? @random.call : Kernel.rand
          jitter = 1 - RETRY_JITTER + (random * RETRY_JITTER * 2)
          [1.0, base * jitter].max
        end

        def clamp(value, minimum, maximum)
          value.clamp(minimum, maximum)
        end

        def wait_before_retry(delay)
          @retry_wait ? @retry_wait.call(delay) : wait_for_retry(delay)
        end

        def wait_for_retry(delay)
          mutex.synchronize do
            return true if stopped?

            shutdown.wait(mutex, delay)
          end

          stopped? || !run_loop?
        end

        def apply_response(response)
          case response.status
          when 200
            apply_configuration(response)
          when 304
            nil
          when 401, 403
            warn_once(:authentication) do
              @logger.warn(
                "Feature Flags agentless endpoint returned HTTP #{response.status}; verify endpoint authentication"
              )
            end
          else
            warn_failure(response, 1)
          end
        end

        def apply_configuration(response)
          configuration = response.body && Parser.parse(response.body)
          unless configuration
            warn_once(:malformed) do
              @logger.error("Feature Flags agentless endpoint returned malformed UFC payload")
            end
            return
          end

          @apply.call(configuration)
          @etag = response.etag.to_s.strip
          @etag = nil if @etag.empty?
        rescue EvaluationEngine::ReconfigurationError => error
          warn_once(:application) do
            @logger.warn("Feature Flags agentless UFC payload could not be applied: #{error.class}: #{error.message}")
          end
        end

        def warn_failure(response, attempts)
          status = response.status
          category = status ? :http : :request
          warn_once(category) do
            if status
              @logger.warn("Feature Flags agentless endpoint returned HTTP #{status} after #{attempts} attempt(s)")
            else
              error_class = response.error ? response.error.class : StandardError
              @logger.warn("Feature Flags agentless request failed after #{attempts} attempt(s): #{error_class}")
            end
          end
        end

        def warn_once(category)
          return if @warned[category]

          @warned[category] = true
          yield
        end
      end
    end
  end
end
