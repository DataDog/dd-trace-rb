if ENV['DD_APPSEC_ENABLED'] == '1'
  begin
    require 'datadog/security'
  rescue Exception => e
    puts "AppSec failed to load. No security check will be performed. error: #{e.message}"
  end

  begin
    if defined?(Rails)
      Datadog::Security.configure do |c|
        options = {}
        c.use :rails, options
      end
    end

    if defined?(Sinatra)
      Datadog::Security.configure do |c|
        options = {}
        c.use :sinatra, options
      end
    end
  rescue Exception => e
    puts "AppSec failed to configure. No security check will be performed. error: #{e.message}"
  end
end
