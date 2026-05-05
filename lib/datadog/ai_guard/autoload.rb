# frozen_string_literal: true

if %w[1 true].include?((Datadog::DATADOG_ENV["DD_AI_GUARD_ENABLED"] || "").downcase)
  begin
    require_relative "contrib/auto_instrument"
    Datadog::AIGuard::Contrib::AutoInstrument.patch_all
  rescue => e
    Kernel.warn("[datadog] AI Guard failed to auto-instrument. error: #{e.class}: #{e}")
  end
end
