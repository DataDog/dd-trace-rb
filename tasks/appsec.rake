namespace :appsec do
  namespace :ruleset do
    task :update do |_task, args|
      require 'uri'
      require 'net/http'

      version = args.to_a[0]

      ['recommended', 'strict'].each do |ruleset|
        uri = URI("https://raw.githubusercontent.com/DataDog/appsec-event-rules/#{version}/build/#{ruleset}.json")

        File.open("lib/datadog/appsec/assets/waf_rules/#{ruleset}.json", 'wb') { |f| f << Net::HTTP::get(uri) }
      end
    end
  end
end
