# Declare shortcuts for Steep::Signature::Ruby to make this file easier to read
# as well as facilitating the findability of violation types emitted by the CLI
# (e.g. the CLI emits `Diagnostic ID: Ruby::UnknownConstant` when finding errors).
Ruby = Steep::Diagnostic::Ruby

target :datadog do
  signature 'sig'

  check 'lib/'

  # This makes Steep check the codebase with the strictest settings.
  # We are free to disable checks if needed inside the block.
  #
  # The default level is `Ruby.default`, and there's an even stricter level called `Ruby.all_error`.
  configure_code_diagnostics(Ruby.strict) do |hash|
    # These checks can be gradually enabled as the codebase cleans up.
    # The reporting levels are:
    # * `:error`, `:warning`: These will fail `rake typecheck` and are always reported by default.
    # * `:information`, `:hint`: To see these, run `rake 'typecheck[--severity-level=information]'`
    #   or `rake 'typecheck[--severity-level=hint]'`

    # These first checks are likely the easiest to fix, given they capture a mismatch
    # between the already declared type in `.rbs` and the actual type inferred by Steep.
    hash[Ruby::DifferentMethodParameterKind] = :information
    hash[Ruby::IncompatibleAssignment] = :information

    # These checks are a bit harder, because they represent the lack of sufficient type information.
    hash[Ruby::FallbackAny] = :information
    hash[Ruby::UnknownInstanceVariable] = :information
    hash[Ruby::UnknownRecordKey] = :information

    # This check asks you to type every empty collection used in
    # local variables with an inline type annotation (e.g. `ret = {} #: Hash[Symbol,untyped]`).
    # This pollutes the code base, and demands seemingly unnecessary typing of internal variables.
    # Ideally, these empty collections automatically assume a signature based on its usage inside its method.
    # @see https://github.com/soutaro/steep/pull/1338
    hash[Ruby::UnannotatedEmptyCollection] = :information

    # This one is funny: it is raised whenever we use `super` from a method in a Module.
    # Since there's no guarantee that the module will be included in a class with the matching method,
    # Steep cannot know if the `super` call will be valid.
    # But this is very common in the codebase, as such module are used for monkey-patching.
    hash[Ruby::UnexpectedSuper] = :information
  end

  ignore 'lib/datadog/appsec.rb'
  ignore 'lib/datadog/appsec/component.rb'
  # Excluded due to https://github.com/soutaro/steep/issues/1232
  ignore 'lib/datadog/appsec/configuration/settings.rb'
  ignore 'lib/datadog/appsec/contrib/'
  ignore 'lib/datadog/appsec/monitor/gateway/watcher.rb'
  ignore 'lib/datadog/core.rb'
  ignore 'lib/datadog/core/buffer/random.rb'
  ignore 'lib/datadog/core/buffer/thread_safe.rb'
  ignore 'lib/datadog/core/configuration.rb'
  ignore 'lib/datadog/core/configuration/base.rb'
  ignore 'lib/datadog/core/configuration/components.rb'
  ignore 'lib/datadog/core/configuration/ext.rb'
  ignore 'lib/datadog/core/configuration/option.rb'
  ignore 'lib/datadog/core/configuration/option_definition.rb'
  ignore 'lib/datadog/core/configuration/options.rb'
  ignore 'lib/datadog/core/configuration/settings.rb'
  ignore 'lib/datadog/core/contrib/rails/utils.rb'
  ignore 'lib/datadog/core/encoding.rb'
  ignore 'lib/datadog/core/environment/identity.rb'
  ignore 'lib/datadog/core/environment/platform.rb'
  ignore 'lib/datadog/core/environment/socket.rb'
  ignore 'lib/datadog/core/environment/variable_helpers.rb'
  ignore 'lib/datadog/core/environment/vm_cache.rb'
  ignore 'lib/datadog/core/error.rb'
  ignore 'lib/datadog/core/metrics/client.rb'
  ignore 'lib/datadog/core/metrics/helpers.rb'
  ignore 'lib/datadog/core/metrics/metric.rb'
  ignore 'lib/datadog/core/metrics/options.rb'
  # steep fails in this file due to https://github.com/soutaro/steep/issues/1231
  ignore 'lib/datadog/core/remote/tie.rb'
  # steep gets lost in module inclusions
  ignore 'lib/datadog/core/remote/transport/http/config.rb'
  ignore 'lib/datadog/core/remote/transport/http/negotiation.rb'
  ignore 'lib/datadog/core/runtime/ext.rb'
  ignore 'lib/datadog/core/runtime/metrics.rb'
  ignore 'lib/datadog/core/transport/http/adapters/net.rb'
  ignore 'lib/datadog/core/transport/http/adapters/unix_socket.rb'
  ignore 'lib/datadog/core/utils/at_fork_monkey_patch.rb' # @ivoanjo: I wasn't able to type this one, it's kinda weird
  ignore 'lib/datadog/core/utils/forking.rb'
  ignore 'lib/datadog/core/utils/hash.rb' # Refinement module
  ignore 'lib/datadog/core/utils/network.rb'
  ignore 'lib/datadog/core/utils/time.rb'
  ignore 'lib/datadog/core/vendor/multipart-post/multipart/post/multipartable.rb'
  ignore 'lib/datadog/core/worker.rb'
  ignore 'lib/datadog/core/workers/async.rb'
  ignore 'lib/datadog/core/workers/interval_loop.rb'
  ignore 'lib/datadog/core/workers/polling.rb'
  ignore 'lib/datadog/core/workers/queue.rb'
  ignore 'lib/datadog/core/workers/runtime_metrics.rb'
  ignore 'lib/datadog/di/configuration/settings.rb'
  ignore 'lib/datadog/di/contrib/railtie.rb'
  ignore 'lib/datadog/di/transport/http/api.rb'
  ignore 'lib/datadog/di/transport/http/diagnostics.rb'
  ignore 'lib/datadog/di/transport/http/input.rb'
  # steep thinks the type of the class is 'self', whatever that is,
  # and then complains that this type doesn't have any methods including
  # language basics like 'send' and 'raise'.
  ignore 'lib/datadog/di/probe_notifier_worker.rb'
  ignore 'lib/datadog/kit/appsec/events.rb' # disabled because of https://github.com/soutaro/steep/issues/701
  ignore 'lib/datadog/kit/identity.rb'      # disabled because of https://github.com/soutaro/steep/issues/701
  ignore 'lib/datadog/opentelemetry.rb'
  ignore 'lib/datadog/opentelemetry/api/context.rb'
  ignore 'lib/datadog/opentelemetry/api/trace/span.rb'
  ignore 'lib/datadog/opentelemetry/sdk/configurator.rb'
  ignore 'lib/datadog/opentelemetry/sdk/id_generator.rb'
  ignore 'lib/datadog/opentelemetry/sdk/propagator.rb'
  ignore 'lib/datadog/opentelemetry/sdk/span_processor.rb'
  ignore 'lib/datadog/opentelemetry/sdk/trace/span.rb'
  ignore 'lib/datadog/profiling/scheduler.rb'
  ignore 'lib/datadog/profiling/tag_builder.rb'
  ignore 'lib/datadog/profiling/tasks/setup.rb'
  ignore 'lib/datadog/tracing/buffer.rb'
  ignore 'lib/datadog/tracing/client_ip.rb'
  ignore 'lib/datadog/tracing/component.rb'
  ignore 'lib/datadog/tracing/configuration/ext.rb'
  ignore 'lib/datadog/tracing/configuration/settings.rb'
  ignore 'lib/datadog/tracing/context.rb'
  ignore 'lib/datadog/tracing/contrib/'
  ignore 'lib/datadog/tracing/diagnostics/environment_logger.rb'
  ignore 'lib/datadog/tracing/diagnostics/health.rb'
  ignore 'lib/datadog/tracing/distributed/datadog.rb'
  ignore 'lib/datadog/tracing/distributed/datadog_tags_codec.rb'
  ignore 'lib/datadog/tracing/distributed/propagation.rb'
  ignore 'lib/datadog/tracing/distributed/trace_context.rb'
  ignore 'lib/datadog/tracing/event.rb'
  ignore 'lib/datadog/tracing/metadata/errors.rb'
  ignore 'lib/datadog/tracing/metadata/ext.rb'
  ignore 'lib/datadog/tracing/sampling/matcher.rb'
  ignore 'lib/datadog/tracing/sampling/rate_by_service_sampler.rb'
  ignore 'lib/datadog/tracing/sampling/rule.rb'
  ignore 'lib/datadog/tracing/sampling/rule_sampler.rb'
  ignore 'lib/datadog/tracing/sampling/span/rule.rb'
  ignore 'lib/datadog/tracing/sync_writer.rb'
  ignore 'lib/datadog/tracing/trace_operation.rb'
  ignore 'lib/datadog/tracing/tracer.rb'
  ignore 'lib/datadog/tracing/transport/http.rb'
  ignore 'lib/datadog/tracing/transport/http/api.rb'
  ignore 'lib/datadog/tracing/transport/http/client.rb'
  ignore 'lib/datadog/tracing/transport/http/traces.rb'
  ignore 'lib/datadog/tracing/transport/io/client.rb'
  ignore 'lib/datadog/tracing/transport/io/traces.rb'
  ignore 'lib/datadog/tracing/transport/statistics.rb'
  ignore 'lib/datadog/tracing/transport/trace_formatter.rb'
  ignore 'lib/datadog/tracing/workers.rb'
  ignore 'lib/datadog/tracing/workers/trace_writer.rb'
  ignore 'lib/datadog/tracing/writer.rb'

  # References `RubyVM::YJIT`, which does not have type information.
  ignore 'lib/datadog/core/environment/yjit.rb'

  library 'pathname'
  library 'cgi'
  library 'logger', 'monitor'
  library 'json'
  library 'ipaddr'
  library 'net-http'
  library 'securerandom'
  library 'digest'
  library 'zlib'
  library 'time'
  library 'pp'
  library 'forwardable'

  # Load all dependency signatures from the `vendor/rbs` directory
  repo_path 'vendor/rbs'
  Dir.children('vendor/rbs').each do |vendor_gem|
    library vendor_gem
  end

  # ffi version 1.17 was shipped with invalid rbs types:
  # https://github.com/ffi/ffi/issues/1107
  library 'libddwaf-stub'
  library 'libdatadog'
end
