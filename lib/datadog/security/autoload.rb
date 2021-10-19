if ['1', 'true'].include?(ENV['DD_APPSEC_ENABLED'].downcase)
  begin
    require 'datadog/security'
  rescue Exception => e
    puts "AppSec failed to load. No security check will be performed. error: #{e.message}"
  end

  require 'datadog/security/contrib/auto_instrument'
  Datadog::Security::Contrib::AutoInstrument.patch_all
end
