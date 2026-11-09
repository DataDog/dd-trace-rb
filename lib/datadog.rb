# frozen_string_literal: true

# Load core first so shared helpers (e.g. Datadog::RubyVersion) are available at require-time
require_relative "datadog/core"

# Load tracing
require_relative "datadog/tracing"
require_relative "datadog/tracing/contrib"

# Load other products (must follow tracing)
require_relative "datadog/profiling"
require_relative "datadog/ai_guard"
require_relative "datadog/appsec"
require_relative "datadog/di"
require_relative "datadog/symbol_database/extensions"
require_relative "datadog/data_streams"
require_relative "datadog/open_feature"

# Activate DI automatically on supported Ruby engines but always load its
# settings so that, for example, turning DI off on JRuby does not produce
# exceptions.
require_relative "datadog/di/boot" if RUBY_ENGINE != "jruby"

require_relative "datadog/error_tracking"
require_relative "datadog/kit"
