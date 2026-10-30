# frozen_string_literal: true

if Datadog.configuration.appsec.enabled
  begin
    require_relative "contrib/auto_instrument"
    Datadog::AppSec::Contrib::AutoInstrument.patch_all
  rescue => e
    Kernel.warn(
      "[datadog] AppSec failed to instrument. No security check will be performed. error: " \
      " #{e.class}: #{e.message}",
    )
  end
end
