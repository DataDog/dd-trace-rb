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
            poll_interval_seconds: settings.feature_flags.agentless.poll_interval_seconds,
            request_timeout_seconds: settings.feature_flags.agentless.request_timeout_seconds,
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
          @random = random || -> { Kernel.rand }
          @retry_wait = retry_wait || ->(delay) { wait_for_retry(delay) }
          @etag = nil
          @warned = {}
          @failed_polls = 0
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

        def stop(force_stop = true, timeout = Core::Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT)
          @lifecycle_mutex.synchronize do
            return false if @stopped

            @stopped = true
            self.enabled = false
          end

          super
          @logger.debug { "Feature Flags: stopped agentless configuration polling" }
          true
        end

        def perform
          poll
        # An exception escaping here ends the unsupervised worker thread and freezes configuration.
        rescue => error
          warn_once(:unexpected) do
            @logger.error("Feature Flags agentless poll failed with #{error.class}; polling continues")
          end
        end

        def poll
          attempt = 1

          while attempt <= MAX_ATTEMPTS
            return if stopped?

            response = @transport.get(@etag)
            log_poll_attempt(response, attempt)
            unless retryable?(response)
              apply_response(response)
              return
            end

            if attempt == MAX_ATTEMPTS
              warn_failure(response, attempt)
              return
            end

            delay = retry_delay(attempt)
            @logger.debug { "Feature Flags: retrying agentless configuration poll in #{delay.round(1)}s" }
            return if wait_before_retry(delay)

            attempt += 1
          end
        end

        protected

        def after_fork
          # The child must report its own failures, while the inherited ETag still matches its configuration.
          @warned = {}
          @failed_polls = 0
          nil
        end

        private

        def stopped?
          @lifecycle_mutex.synchronize { @stopped }
        end

        def log_poll_attempt(response, attempt)
          @logger.debug do
            status = response.status
            outcome = case status
            when nil
              "failed: #{request_error_class(response)}"
            when 304
              "configuration unchanged (HTTP 304)"
            when 200
              etag = response.etag.to_s.strip
              etag.empty? ? "configuration received (HTTP 200)" : "configuration received (ETag #{etag}; HTTP 200)"
            else
              "#{http_failure_reason(status)} (HTTP #{status})"
            end
            "Feature Flags: agentless configuration poll attempt #{attempt}/#{MAX_ATTEMPTS}: #{outcome}"
          end
        end

        def http_failure_reason(status)
          case status
          when 400
            "configuration request rejected as invalid"
          when 401
            "configuration request lacks valid authentication credentials"
          when 403
            "access to the configuration endpoint is forbidden"
          when 404
            "configuration endpoint not found"
          when 408
            "configuration request timed out"
          when 429
            "configuration request rate limited"
          when 500
            "configuration endpoint encountered an internal error"
          when 502
            "configuration endpoint received an invalid upstream response"
          when 503
            "configuration endpoint is temporarily unavailable"
          when 504
            "configuration endpoint timed out waiting for an upstream response"
          when 500..599
            "configuration endpoint reported a server error"
          else
            "unexpected response from the configuration endpoint"
          end
        end

        def retryable?(response)
          status = response.status
          return true unless status

          retryable_status?(status)
        end

        def retryable_status?(status)
          status == 408 || status == 429 || status.between?(500, 599)
        end

        def retry_delay(attempt)
          base = if attempt == 1
            clamp(@poll_interval_seconds / 6.0, FIRST_RETRY_MIN_SECONDS, FIRST_RETRY_MAX_SECONDS)
          else
            clamp(@poll_interval_seconds / 3.0, SECOND_RETRY_MIN_SECONDS, SECOND_RETRY_MAX_SECONDS)
          end
          random = @random.call
          jitter = 1 - RETRY_JITTER + (random * RETRY_JITTER * 2)
          [1.0, base * jitter].max
        end

        def clamp(value, minimum, maximum)
          value.clamp(minimum, maximum)
        end

        def wait_before_retry(delay)
          @retry_wait.call(delay)
        end

        def wait_for_retry(delay)
          mutex.synchronize do
            return true if stopped?

            shutdown.wait(mutex, delay)
          end

          stopped? || !run_loop?
        end

        def apply_response(response)
          status = response.status
          case status
          when 200
            log_recovery
            apply_configuration(response)
          when 304
            log_recovery
          when 401, 403
            report_poll_failure(
              :authentication,
              "Feature Flags agentless #{http_failure_reason(status)}; verify endpoint authentication (HTTP #{status})",
            )
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
            @logger.debug do
              "Feature Flags: ignoring malformed agentless configuration payload"
            end
            return
          end

          @apply.call(configuration)
          etag = response.etag.to_s.strip
          @etag = etag.empty? ? nil : etag
        rescue EvaluationEngine::ReconfigurationError => error
          warn_once(:application) do
            @logger.warn("Feature Flags agentless UFC payload could not be applied: #{error.class}: #{error.message}")
          end
        end

        def warn_failure(response, attempts)
          status = response.status
          category = if status.nil?
            :request
          elsif retryable_status?(status)
            :http_retryable
          else
            :http_unexpected
          end
          refresh = (attempts == MAX_ATTEMPTS) ? "; next poll in #{@poll_interval_seconds}s" : ""
          message = if status
            "Feature Flags agentless #{http_failure_reason(status)} after #{attempts} attempt(s) (HTTP #{status})#{refresh}"
          else
            "Feature Flags agentless request failed after #{attempts} attempt(s): #{request_error_class(response)}#{refresh}"
          end
          report_poll_failure(category, message)
        end

        # Repeats are debug-only so a persistent outage does not flood warnings.
        def report_poll_failure(category, message)
          @failed_polls += 1
          if @warned[category]
            @logger.debug { message }
          else
            warn_once(category) { @logger.warn(message) }
          end
        end

        def log_recovery
          return if @failed_polls.zero?

          failed_polls = @failed_polls
          @failed_polls = 0
          @logger.debug { "Feature Flags: agentless configuration delivery recovered after #{failed_polls} failed poll(s)" }
        end

        # Class only: transport error messages can embed endpoint details.
        def request_error_class(response)
          response.error ? response.error.class : StandardError
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
