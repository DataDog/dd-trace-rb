namespace :appsec do
  namespace :ruleset do
    task :update do |_task, args|
      require 'uri'
      require 'net/http'

      version = args.to_a[0]
      raise ArgumentError, 'You must provide a version' if version.nil?

      # You need to generate a token with the `repo` scope
      # and configure SSO for DataDog's GitHub organization
      token = ENV['GITHUB_TOKEN']
      raise ArgumentError, 'You must set GITHUB_TOKEN env variable' if token.nil?

      ['recommended', 'strict'].each do |ruleset|
        uri = URI("https://api.github.com/repos/DataDog/appsec-event-rules/contents/build/#{ruleset}.json?ref=#{version}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        req = Net::HTTP::Get.new(uri)
        req['Authorization'] = "Bearer #{token}"
        req['Accept'] = 'application/vnd.github.raw+json'

        http.request(req) do |res|
          case res
          when Net::HTTPSuccess
            File.open("lib/datadog/appsec/assets/waf_rules/#{ruleset}.json", 'wb') do |f|
              res.read_body do |chunk|
                f << chunk
              end
            end
          else
            raise "Failed to download #{ruleset}.json: #{response.code} #{response.message}"
          end
        end
      end
    end
  end
end
