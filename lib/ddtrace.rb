# frozen_string_literal: true

# Load tracing
require_relative 'datadog/tracing'
require_relative 'datadog/tracing/contrib'

# Load other products (must follow tracing)
require_relative 'datadog/profiling'
require_relative 'datadog/appsec'
require 'datadog/ci'
require_relative 'datadog/kit'

module DDKernel
  INSTRUMENTED_GEMS = Datadog.registry.flat_map do |entry|
    entry.gems.map { |gem| [gem.to_s, entry.name] } # TODO: Remove `#to_s`
  end.to_h

  def require(name)
    just_loaded = super

    begin
      if just_loaded && INSTRUMENTED_GEMS.include?(name)
        puts "GOT IT: #{name}"
        Datadog.logger.debug { "Detected '#{name}' gem loaded, instrumenting it." }
        Datadog.configure do |c|
          c.tracing.instrument INSTRUMENTED_GEMS[name]
        end
      end
    rescue => e
      Datadog.logger.debug { "Failed to instrument gem '#{name}': #{e.class.name} #{e.message} at #{Array(e.backtrace).join("\n")}" }
    end

    just_loaded
  end

  ::Kernel.prepend(self)
end

Datadog.configure do |c|
  c.diagnostics.debug = true
end

require 'rake'

puts 'done'