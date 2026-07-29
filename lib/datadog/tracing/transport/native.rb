# frozen_string_literal: true

require "json"
require_relative "trace_formatter"
require_relative "statistics"

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

          attr_reader :logger

          # @param agent_settings [Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings]
          #   Agent connection settings (provides +#url+).
          # @param logger [Logger]
          def initialize(agent_settings:, logger:)
            unless Native.supported?
              raise "Native transport is not supported: #{UNSUPPORTED_REASON}"
            end

            @logger = logger

            # Guards the one-shot warning about span fields the native exporter
            # does not yet convert (see #warn_unsupported_fields!).
            @unsupported_fields_warned = false

            # Serializes native sends and is held across a fork. See the
            # fork-safety note below.
            @send_mutex = Mutex.new

            # Serializes fork-hook execution with close/finalization. Unlike
            # @send_mutex, this is held for the complete fork lifecycle so the
            # matching parent/child hooks cannot be deregistered mid-fork.
            @fork_mutex = Mutex.new
            @fork_state = {closed: false, pending: 0, forking: false, finalize: false}

            url = agent_settings.url
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
              tracer_version: tracer_version,
              language: language,
              language_version: language_version,
              language_interpreter: language_interpreter,
              hostname: hostname,
              env: env,
              service: service,
              version: version
            )
            @exporter = exporter

            # Fork safety: the native exporter owns a long-lived tokio runtime
            # with background worker threads. Around a fork we must quiesce the
            # runtime before forking and restore it afterwards in both the parent
            # and the child (where the inherited runtime is dead).
            #
            # A libdatadog Rust call must NOT be interrupted by `fork()`. A
            # native send releases the GVL during the Rust
            # `ddog_trace_exporter_send_trace_chunks` call, so if another thread
            # forks while a (typically the writer/`AsyncTransport`) thread is
            # mid-send, the child would inherit a half-completed send and
            # Rust-internal locks, deadlocking or crashing. `_native_before_fork`
            # also tears down and replaces the runtime, so it must not run while
            # a send is still using that runtime.
            #
            # `@fork_mutex` prevents close/finalization from deregistering the
            # completion hooks after `:before` has started. The `:before` hook
            # locks it first, then calls `_native_before_fork`, and finally
            # locks `@send_mutex`, which serializes sends and is held across the
            # fork. This lock order is also used by #close; sends only acquire
            # `@send_mutex`, so there is no inverse path.
            #
            # `_native_before_fork` must run before locking `@send_mutex` to
            # pause the runtime before waiting for an in-flight send to drain.
            # The hook first calls
            # `_native_before_fork` to pause the runtime, THEN locks the mutex.
            # This ordering minimizes the serialized section and is safe to run
            # concurrently with an in-flight send: `block_on` (used by
            # `send_trace_chunks`) only briefly locks the runtime mutex to clone
            # the `Arc<Runtime>` (or build a throwaway `current_thread` runtime
            # if it has been taken) and then drives the send on its own clone
            # holding no mutex, while `_native_before_fork` just `take()`s the
            # shared `Arc` and pauses workers -- so neither deadlocks the other.
            # Locking the mutex AFTER `_native_before_fork` still guarantees the
            # drain: it BLOCKS until any in-flight send finishes (bounded by the
            # exporter's request timeout), which drops the send's last `Arc` and
            # fully shuts the runtime down, and prevents new sends from starting.
            # The lock is released in the `:parent` and `:child` hooks. In
            # practice only one writer thread sends, so serializing adds no real
            # contention.
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
            # historically-created exporter. The closures intentionally capture
            # only locals (NOT `self`), so the Transport stays GC-eligible and
            # its finalizer can fire even when #close was not called explicitly.
            send_mutex = @send_mutex
            fork_mutex = @fork_mutex
            fork_state = @fork_state
            remove_fork_hooks = nil
            before_hook = Core::Utils::AtForkMonkeyPatch.at_fork(:before) do
              # Announce before blocking: close may already hold @fork_mutex
              # while it waits for a send, and must yield to this hook rather
              # than deregistering its matching parent/child hooks.
              fork_state[:pending] += 1
              begin
                fork_mutex.lock
              ensure
                fork_state[:pending] -= 1
              end

              if fork_state[:closed]
                fork_mutex.unlock
                next
              end
              fork_state[:forking] = true

              begin
                # Pause the runtime first (safe to run concurrently with an
                # in-flight send), then drain by locking the mutex. The lock
                # must happen even if `_native_before_fork` raises, so the
                # in-flight send has returned before the fork. Held across the
                # fork; released in :parent/:child.
                exporter._native_before_fork
              rescue => e
                Datadog.logger.warn { "Native transport before-fork preparation failed; traces may not be sent to Datadog: #{e.class}: #{e.message}" }
              ensure
                send_mutex.lock
              end
            end
            parent_hook = Core::Utils::AtForkMonkeyPatch.at_fork(:parent) do
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
              fork_state[:forking] = false
              remove_fork_hooks.call if fork_state[:finalize]
              fork_mutex.unlock if fork_mutex.owned?
            end
            child_hook = Core::Utils::AtForkMonkeyPatch.at_fork(:child) do
              exporter._native_after_fork_in_child if fork_mutex.owned?
            rescue => e
              Datadog.logger.warn { "Native transport after-fork reset failed; traces may not be sent to Datadog: #{e.class}: #{e.message}" }
            ensure
              # See the :parent hook: normally owned (the forking thread is the
              # lone survivor in the child); the guard only covers `:before`
              # being interrupted mid-lock.
              send_mutex.unlock if send_mutex.owned?
              fork_state[:forking] = false
              remove_fork_hooks.call if fork_state[:finalize]
              fork_mutex.unlock if fork_mutex.owned?
            end

            @fork_hooks = {before: before_hook, parent: parent_hook, child: child_hook}
            remove_fork_hooks = self.class.send(:fork_hooks_remover, @fork_hooks, fork_state)

            # Fallback so a dropped (un-#close'd) transport doesn't leak its
            # global fork hooks (and, through them, the exporter/runtime). The
            # finalizer proc is built by a class method capturing ONLY the
            # stage->block handles, never `self` -- a finalizer that closed over
            # the object it is attached to would keep that object reachable and
            # never run.
            ObjectSpace.define_finalizer(
              self,
              self.class.send(:finalizer_for, fork_mutex, fork_state, remove_fork_hooks)
            )
          end

          # Deregister this transport's process-global fork hooks and release the
          # native exporter so its runtime can shut down. Idempotent: safe to
          # call multiple times and safe to call after the finalizer has run.
          def close
            # Acquire both locks only when no before-fork hook is already
            # waiting. A hook can announce itself while we wait for an active
            # send, so check again after acquiring @send_mutex.
            loop do
              @fork_mutex.lock
              if @fork_state[:pending] > 0
                @fork_mutex.unlock
                Thread.pass
                next
              end

              @send_mutex.lock
              break if @fork_state[:pending] == 0

              @send_mutex.unlock
              @fork_mutex.unlock
              Thread.pass
            end

            fork_hooks = @fork_hooks
            return if fork_hooks.nil?

            @fork_state[:closed] = true
            @fork_hooks = nil

            fork_hooks.each do |stage, block|
              Core::Utils::AtForkMonkeyPatch.remove_at_fork(stage, block)
            end

            # Drop our reference to the exporter so that, once the hooks above
            # no longer pin it, it can be collected and its runtime shut down
            # cleanly in this (parent) process.
            @exporter = nil

            # The finalizer only exists to deregister the hooks for a transport
            # dropped without #close. We have just done that, so remove it;
            # otherwise its captured hook blocks keep the exporter alive until
            # this transport is itself collected.
            ObjectSpace.undefine_finalizer(self)

            nil
          ensure
            @send_mutex.unlock if @send_mutex.owned?
            @fork_mutex.unlock if @fork_mutex.owned?
          end

          # Builds the finalizer proc for a transport's fork hooks.
          #
          # Defined as a class method so the proc closes over ONLY the
          # stage->block handles passed in and never over a Transport instance
          # (which would keep the instance reachable and prevent the finalizer
          # from ever running). Removing the hooks unpins the exporter captured
          # by those closures, allowing it (and its runtime) to be freed.
          def self.fork_hooks_remover(fork_hooks, fork_state)
            proc do
              fork_state[:closed] = true
              fork_state[:finalize] = false
              fork_hooks.each do |stage, block|
                Core::Utils::AtForkMonkeyPatch.remove_at_fork(stage, block)
              end
            end
          end
          private_class_method :fork_hooks_remover

          def self.finalizer_for(fork_mutex, fork_state, remove_fork_hooks)
            proc do
              # Mutex is not reentrant. A finalizer can run at a safe point on
              # the owning thread, so either remove directly or let the active
              # fork's completion callback restore state before removing.
              if fork_mutex.owned?
                if fork_state[:forking]
                  # The matching parent/child callback must restore the runtime
                  # and release both locks before deregistering its own hooks.
                  fork_state[:finalize] = true
                else
                  remove_fork_hooks.call
                end
                next
              end

              loop do
                fork_mutex.lock
                break if fork_state[:pending] == 0

                fork_mutex.unlock
                Thread.pass
              end

              begin
                remove_fork_hooks.call
              ensure
                fork_mutex.unlock if fork_mutex.owned?
              end
            end
          end
          private_class_method :finalizer_for

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
            traces.each { |trace| TraceFormatter.format!(trace) }

            # Build the Array<Array<Span>> structure expected by the C extension.
            # Each trace segment becomes one inner array (one trace chunk).
            chunks = traces.map(&:spans)

            # The native exporter only serializes scalar fields plus meta and
            # metrics; span events, span links, and meta_struct are not yet
            # converted and would be dropped. Warn (once) so the loss is visible.
            warn_unsupported_fields!(chunks)

            # Serialize the native send and hold the mutex across it so a
            # concurrent fork's :before hook blocks until this send drains
            # (and `_native_before_fork` cannot tear down the runtime mid-send).
            # `Mutex#synchronize` releases on exception / `rb_jump_tag` via its
            # ensure, so interrupt propagation stays correct.
            responses = @send_mutex.synchronize do
              # Resolve the exporter under the same lock used by #close, so
              # close either drains this send or prevents it from starting.
              exporter = @exporter
              raise "Native transport has been closed" if exporter.nil?

              exporter._native_send_traces(chunks)
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

          # Warn, at most once per transport, when a batch contains span fields
          # the native exporter does not yet convert (span events, span links,
          # meta_struct). These are silently dropped by the native path; full
          # support is tracked separately. The check is cheap: the fields are
          # already-materialized collections on each Span.
          def warn_unsupported_fields!(chunks)
            return if @unsupported_fields_warned

            unsupported = []
            chunks.each do |spans|
              spans.each do |span|
                unsupported << "span events" if span.events.any?
                unsupported << "span links" if span.links.any?
                unsupported << "meta_struct" unless span.metastruct.to_h.empty?
              end
            end
            return if unsupported.empty?

            @unsupported_fields_warned = true
            fields = unsupported.uniq.join(", ")
            logger.warn do
              "Native transport does not yet support: #{fields}. This data will not be sent to Datadog. " \
                "Unset DD_EXPERIMENTAL_NATIVE_TRANSPORT_ENABLED to use the default transport if you rely on these."
            end
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
