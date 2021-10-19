if ENV['DD_APPSEC_ENABLED'] == '1'
  begin
    require 'datadog/security'
  rescue Exception => e
    puts "AppSec failed to load. No security check will be performed. error: #{e.message}"
  end

  require 'datadog/security/contrib/auto_instrument'
  Datadog::Security::Contrib::AutoInstrument.patch_all
end
