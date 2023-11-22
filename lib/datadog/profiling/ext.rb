# frozen_string_literal: true

module Datadog
  module Profiling
    module Ext
      ENV_ENABLED = 'DD_PROFILING_ENABLED'
      ENV_UPLOAD_TIMEOUT = 'DD_PROFILING_UPLOAD_TIMEOUT'
      ENV_MAX_FRAMES = 'DD_PROFILING_MAX_FRAMES'
      ENV_AGENTLESS = 'DD_PROFILING_AGENTLESS'
      ENV_ENDPOINT_COLLECTION_ENABLED = 'DD_PROFILING_ENDPOINT_COLLECTION_ENABLED'

      # Allocation sampling is safe and supported on Ruby 2.x, but has a few caveats on Ruby 3.x.
      #
      # TL;DR: Supported on (2.x, 3.1.4+, 3.2.3+, and 3.3.0+).
      #
      # Caveat 1 (severe):
      # On Ruby versions 3.0 (all), 3.1.0 to 3.1.3, and 3.2.0 to 3.2.2 this is disabled by default because it
      # can trigger a VM bug that causes a segmentation fault during garbage collection of Ractors
      # (https://bugs.ruby-lang.org/issues/18464). We don't recommend using this feature on such Rubies.
      # This bug is fixed on Ruby versions 3.1.4, 3.2.3 and 3.3.0.
      #
      # Caveat 2 (annoyance):
      # On all known versions of Ruby 3.x, due to https://bugs.ruby-lang.org/issues/19112, when a ractor gets
      # garbage collected, Ruby will disable all active tracepoints, which this feature internally relies on.
      # Thus this feature is only usable if you're not using Ractors.
      #
      # Caveat 3 (severe):
      # Ruby 3.2.0 to 3.2.2 have a bug in the newobj tracepoint (https://bugs.ruby-lang.org/issues/19482,
      # https://github.com/ruby/ruby/pull/7464) so that's an extra reason why it's not safe on those Rubies.
      # This bug is fixed on Ruby versions 3.2.3 and 3.3.0.
      IS_ALLOCATION_SAMPLING_SUPPORTED = RUBY_VERSION.start_with?('2.') ||
        (RUBY_VERSION.start_with?('3.1.') && RUBY_VERSION >= '3.1.4') ||
        (RUBY_VERSION.start_with?('3.2.') && RUBY_VERSION >= '3.2.3') ||
        RUBY_VERSION >= '3.3.'

      module Transport
        module HTTP
          FORM_FIELD_TAG_ENV = 'env'
          FORM_FIELD_TAG_HOST = 'host'
          FORM_FIELD_TAG_LANGUAGE = 'language'
          FORM_FIELD_TAG_PID = 'process_id'
          FORM_FIELD_TAG_PROFILER_VERSION = 'profiler_version'
          FORM_FIELD_TAG_RUNTIME = 'runtime'
          FORM_FIELD_TAG_RUNTIME_ENGINE = 'runtime_engine'
          FORM_FIELD_TAG_RUNTIME_ID = 'runtime-id'
          FORM_FIELD_TAG_RUNTIME_PLATFORM = 'runtime_platform'
          FORM_FIELD_TAG_RUNTIME_VERSION = 'runtime_version'
          FORM_FIELD_TAG_SERVICE = 'service'
          FORM_FIELD_TAG_VERSION = 'version'

          PPROF_DEFAULT_FILENAME = 'rubyprofile.pprof'
          CODE_PROVENANCE_FILENAME = 'code-provenance.json'
        end
      end
    end
  end
end
