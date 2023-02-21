# typed: ignore

if %w[1 true].include?((ENV['DD_APPSEC_ENABLED'] || '').downcase)
  require_relative '../../ddtrace'

  begin
    require_relative 'contrib/auto_instrument'
    Datadog::AppSec::Contrib::AutoInstrument.patch_all
  rescue StandardError => e
    puts "AppSec failed to instrument. No security check will be performed. error: #{e.class.name} #{e.message}"
  end
end
