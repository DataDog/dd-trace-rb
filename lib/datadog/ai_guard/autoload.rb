# frozen_string_literal: true

if Datadog.configuration.ai_guard.enabled
  begin
    require_relative "contrib/auto_instrument"
    Datadog::AIGuard::Contrib::AutoInstrument.patch_all
  rescue => e
    Kernel.warn("[datadog] AI Guard failed to auto-instrument. error: #{e.class}: #{e.message}")
  end
end
