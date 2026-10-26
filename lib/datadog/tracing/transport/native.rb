# frozen_string_literal: true

require "json"
require_relative "trace_formatter"
require_relative "statistics"
require_relative "span_events_negotiation"
require_relative "native/telemetry"

module Datadog
  module Tracing
    module Transport
      # Transport backed by the native trace exporter (Rust via C FFI).
      #
      # Converts Ruby Span objects directly to Rust spans and delegates
      # serialization and sending to the Rust data pipeline, which handles
      # stats computation, msgpack encoding, and HTTP transport with retry
      # logic.
      #
      # Implements the same +send_traces+ / +stats+ interface as
      # {Datadog::Tracing::Transport::Traces::Transport} so it can be used
      # as a drop-in replacement via the +Writer+'s +:transport+ option.
      module Native
        # Returns +nil+ when the native extension is available, or a +String+
        # describing why it is not.
        UNSUPPORTED_REASON = begin
          require "datadog/core"
          Datadog::Core::LIBDATADOG_API_FAILURE
        rescue => e
          e.message
        end

        def self.supported?
          UNSUPPORTED_REASON.nil?
        end

        # +TraceExporter+ and +TracerSpan+ are defined by the C extension in
        # +ext/libdatadog_api/trace_exporter.c+ and become available after the
        # native extension is loaded. +Response+ is a plain Ruby class (see
        # +native/response.rb+); the C side only resolves and instantiates it.
        #
        # The hierarchy is:
        #   Datadog::Tracing::Transport::Native::TraceExporter (C)
        #   Datadog::Tracing::Transport::Native::TracerSpan (C)
        #   Datadog::Tracing::Transport::Native::Response (Ruby)

        # Drop-in transport that delegates to the native trace exporter.
        class Transport
          include Statistics
          include SpanEventsNegotiation

          attr_reader :logger, :url

          def telemetry=(client)
            @send_mutex.synchronize do
              if (reporter = @telemetry)
                reporter.client = client
              elsif @exporter
                @telemetry = Telemetry.new(client)
              end
            end
          end

          # @param agent_settings [Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings]
          #   Agent connection settings, including the request timeout.
          # @param logger [Logger]
          def initialize(agent_settings:, logger:)
            unless Native.supported?
              raise "Native transport is not supported: #{UNSUPPORTED_REASON}"
            end

            @logger = logger
            @telemetry = nil

            # Serializes native sends and is held across a fork. See the
            # fork-safety note below.
            @send_mutex = Mutex.new

            # Serializes concurrent fork-hook lifecycles. Unlike @send_mutex,
            # this is held across the fork through the matching completion hook.
            @fork_mutex = Mutex.new

            @url = agent_settings.url
            tracer_version = tracer_version_string
            language = Core::Environment::Ext::LANG
            language_version = Core::Environment::Ext::LANG_VERSION
            language_interpreter = Core::Environment::Ext::LANG_INTERPRETER
            hostname = begin
              Core::Environment::Socket.hostname
            rescue
              nil
            end
            env = Datadog.configuration.env
            service = Datadog.configuration.service
            version = Datadog.configuration.version

            exporter = Native::TraceExporter._native_new(
              url: url,
              timeout_milliseconds: agent_settings.timeout_seconds * 1000,
              tracer_version: tracer_version,
              language: language,
              language_version: language_version,
              language_interpreter: language_interpreter,
              hostname: hostname,
              env: env,
              service: service,
              version: version,
              client_computed_stats: !Datadog.configuration.apm.tracing.enabled
            )
            @exporter = exporter

            # Fork safety: the native exporter owns a long-lived tokio runtime
            # with background worker threads. Around a fork we must quiesce the
            # runtime before forking and restore it afterwards in both the parent
            # and the child (where the inherited runtime is dead).
            #
            # A native send releases the GVL. Forking before it unwinds could
            # leave the child with Rust locks held by a vanished thread.
            #
            # `@fork_mutex` serializes concurrent forks for this exporter. The
            # `:before` hook locks it first, then calls `_native_before_fork`,
            # and finally locks `@send_mutex`, which serializes sends and is
            # held across the fork. Close takes the same lock order; sends take
            # only @send_mutex and cannot close the transport re-entrantly.
            #
            # Cancel before waiting for @send_mutex, so split batches stop
            # dispatching. Unattempted chunks are discarded; in-flight delivery
            # is uncertain. The mutex waits for cleanup, not delivery, before
            # the fork. The send drives its own Arc<Runtime> without holding the
            # runtime mutex, so worker pause and cancellation can run concurrently.
            # Parent/child hooks restore admission even after a clean restart
            # failure: subsequent sends can use libdatadog's temporary runtime.
            #
            # Note: the `:before` block runs before genuine forks (web-server
            # workers, `Process.daemon`) that go through `Process._fork`. It
            # does NOT run for `system`/backtick/`IO.popen`/`Process.spawn`,
            # which spawn via `posix_spawn`/`vfork`+`exec` and replace the
            # process image rather than carrying over the parent's work. Keeping
            # it cheap is still worthwhile since real forks can be frequent.
            #
            # The hooks below are process-global and are never auto-removed by
            # the fork machinery, so each transport must deregister its own
            # hooks when it goes away (see #close and the finalizer): otherwise
            # the closures keep the exporter -- and its runtime threads -- alive
            # forever, and every later fork runs them against every
            # historically-created exporter. The closures intentionally close
            # over only locals (NOT `self`), so the Transport stays GC-eligible and
            # its finalizer can fire even when #close was not called explicitly.
            send_mutex = @send_mutex
            fork_mutex = @fork_mutex
            before_hook = proc do
              fork_mutex.lock

              begin
                # The send must unwind before fork even if worker pause fails.
                exporter._native_before_fork
              rescue => e
                Datadog.logger.warn { "Native transport before-fork preparation failed; traces may not be sent to Datadog: #{e.class}: #{e.message}" }
              ensure
                send_mutex.lock
              end
            end
            parent_hook = proc do
              exporter._native_after_fork_in_parent if fork_mutex.owned?
            rescue => e
              Datadog.logger.warn { "Native transport after-fork reset failed; traces may not be sent to Datadog: #{e.class}: #{e.message}" }
            ensure
              # `:before`'s ensure always locks the mutex on the forking thread
              # before any fork outcome, so it is normally owned here; the guard
              # only covers `:before` being interrupted mid-lock (e.g. a kill
              # between `_native_before_fork` and the lock). Released even if the
              # native call raised, so a failure can't leave the mutex locked.
              send_mutex.unlock if send_mutex.owned?
              fork_mutex.unlock if fork_mutex.owned?
            end
            child_hook = proc do
              exporter._native_after_fork_in_child if fork_mutex.owned?
            rescue => e
              Datadog.logger.warn { "Native transport after-fork reset failed; traces may not be sent to Datadog: #{e.class}: #{e.message}" }
            ensure
              # See the :parent hook: normally owned (the forking thread is the
              # lone survivor in the child); the guard only covers `:before`
              # being interrupted mid-lock.
              send_mutex.unlock if send_mutex.owned?
              fork_mutex.unlock if fork_mutex.owned?
            end

            @fork_hooks = Core::Utils::AtForkMonkeyPatch.at_fork_blocks(
              before: before_hook,
              parent: parent_hook,
              child: child_hook
            )
            remove_fork_hooks = self.class.send(:fork_hooks_remover, @fork_hooks)

            # Fallback so a dropped (un-#close'd) transport doesn't leak its
            # global fork hooks (and, through them, the exporter/runtime). The
            # removal proc is built by a class method capturing ONLY the
            # stage->block handles, never `self` -- a finalizer that closed over
            # the object it is attached to would keep that object reachable and
            # never run. A fork that already copied these callbacks still owns
            # them through its matching completion stage.
            ObjectSpace.define_finalizer(
              self,
              remove_fork_hooks
            )
          end

          # Deregister this transport's process-global fork hooks and release the
          # native exporter so its runtime can shut down. Idempotent: safe to
          # call multiple times and safe to call after the finalizer has run.
          def close
            raise ThreadError, "Cannot close native transport from its sending thread" if @send_mutex.owned?
            @fork_mutex.synchronize do
              exporter = @exporter
              begin
                exporter&._native_cancel_pending
                @send_mutex.synchronize do
                  hooks = @fork_hooks
                  return if hooks.nil?

                  begin
                    @exporter&._native_close
                  ensure
                    @fork_hooks = nil
                    @telemetry = nil
                    @exporter = nil
                    hooks.each do |stage, block|
                      Core::Utils::AtForkMonkeyPatch.remove_at_fork(stage, block)
                    end
                    ObjectSpace.undefine_finalizer(self)
                  end
                end
              ensure
                exporter&._native_resume_sends if @exporter.equal?(exporter)
              end
            end

            nil
          end

          # Builds the proc that deregisters a transport's fork hooks.
          #
          # Defined as a class method so the proc closes over ONLY the
          # stage->block handles passed in and never over a Transport instance
          # (which would keep the instance reachable and prevent the finalizer
          # from ever running). Removing the hooks unpins the exporter captured
          # by those closures, allowing it (and its runtime) to be freed.
          def self.fork_hooks_remover(fork_hooks)
            proc do
              fork_hooks.each do |stage, block|
                Core::Utils::AtForkMonkeyPatch.remove_at_fork(stage, block)
              end
            end
          end
          private_class_method :fork_hooks_remover

          # Send a list of traces to the agent.
          #
          # Each trace is a {Datadog::Tracing::TraceSegment} whose +#spans+
          # returns an +Array+ of {Datadog::Tracing::Span}.
          #
          # @param traces [Array<Datadog::Tracing::TraceSegment>]
          # @return [Array<Response>] one response per batch sent
          def send_traces(traces)
            return [] if traces.empty?

            # Apply trace-level tags to root spans (same as the HTTP transport)
            traces.each { |trace| TraceFormatter.format!(trace, transport: "native") }

            # Build the Array<Array<Span>> structure expected by the C extension.
            # Each trace segment becomes one inner array (one trace chunk).
            chunks = traces.map(&:spans)

            native_events_supported = native_events_supported?
            apply_legacy_span_events!(chunks, native_events_supported)

            # Fork preparation cancels and pauses first, then acquires this mutex
            # to ensure the sender has unwound before the process forks.
            # `Mutex#synchronize` releases on exception / `rb_jump_tag` via its
            # ensure, so interrupt propagation stays correct.
            responses = @send_mutex.synchronize do
              # Resolve the exporter under the same lock used by #close, so
              # close cannot free the exporter while this sender unwinds.
              exporter = @exporter
              raise "Native transport has been closed" if exporter.nil?

              exporter._native_send_traces(chunks, native_events_supported) do |observations|
                dropped = observations.fetch(:chunks_dropped_payload_too_large, 0)
                Datadog.health_metrics.transport_trace_too_large(dropped) if dropped > 0
                @telemetry&.record(observations)
              end
            end

            # Update statistics from the response
            responses.each { |response| update_stats_from_response!(response) }

            responses
          rescue => e
            logger.debug { "Native transport error: #{e.class} #{e.message}" }
            update_stats_from_exception!(e)
            [InternalErrorResponse.new(e)]
          end

          private

          # Writes each span's events into the legacy JSON +events+ meta tag
          # when the agent lacks typed-event support, mutating spans in place.
          #
          # @param chunks [Array<Array<Datadog::Tracing::Span>>] trace chunks to serialize
          # @param native_events_supported [Boolean] whether the agent accepts typed events
          # @return [void]
          def apply_legacy_span_events!(chunks, native_events_supported)
            return if native_events_supported

            chunks.each do |spans|
              spans.each do |span|
                next if span.events.empty?

                span.set_tag("events", span.events.map(&:to_hash).to_json)
              end
            end

            nil
          end

          def tracer_version_string
            defined?(Datadog::VERSION::STRING) ? Datadog::VERSION::STRING : "unknown"
          end
        end

        # Response for internal errors (exceptions raised before reaching
        # the native transport).
        class InternalErrorResponse
          attr_reader :error

          def initialize(error)
            @error = error
          end

          def ok?
            false
          end

          def internal_error?
            true
          end

          def server_error?
            false
          end

          def client_error?
            false
          end

          def not_found?
            false
          end

          def unsupported?
            false
          end

          def payload
            nil
          end

          def trace_count
            0
          end

          def service_rates
            nil
          end

          def inspect
            "#<#{self.class} error=#{error.inspect}>"
          end
        end
      end
    end
  end
end
