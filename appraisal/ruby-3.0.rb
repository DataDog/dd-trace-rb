appraise 'rails61-mysql2' do
  gem 'rails', '~> 6.1.0'
  gem 'mysql2', '~> 0.5', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'net-smtp'
end

appraise 'rails61-postgres' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'net-smtp'
end

appraise 'rails61-postgres-redis' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'net-smtp'
end

appraise 'rails61-postgres-sidekiq' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sidekiq', '>= 6.1.2'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'rails_semantic_logger', '~> 4.0'
  gem 'net-smtp'
end

appraise 'rails61-semantic-logger' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
  gem 'net-smtp'
end

appraise 'rails61-trilogy' do
  gem 'rails', '~> 6.1.0'
  gem 'trilogy'
  gem 'activerecord-trilogy-adapter'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'net-smtp'
end

appraise 'rails7' do
  gem 'rails', '~> 7.0.0'
end

appraise 'rails71' do
  gem 'rails', '~> 7.1.0'
end

appraise 'rails-old-redis' do
  # All dependencies except Redis < 4 are not important, they are just required to run Rails tests.
  gem 'redis', '< 4'
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'resque2-redis3' do
  gem 'redis', '< 4.0'
  gem 'resque', '>= 2.0'
end

appraise 'resque2-redis4' do
  gem 'redis', '>= 4.0'
  gem 'resque', '>= 2.0'
end

appraise 'aws' do
  gem 'aws-sdk'
  gem 'shoryuken'
end

appraise 'http' do
  gem 'ethon'
  gem 'http'
  gem 'httpclient'
  gem 'typhoeus'
end

build_coverage_matrix('stripe', 7..12, min: '5.15.0')
build_coverage_matrix('opensearch', [2], gem: 'opensearch-ruby')
build_coverage_matrix('elasticsearch', [7])
build_coverage_matrix('faraday')
build_coverage_matrix('excon')
build_coverage_matrix('rest-client')
build_coverage_matrix('mongo', min: '2.1.0')
build_coverage_matrix('dalli', [2])
build_coverage_matrix('devise', min: '3.2.1')

appraise 'karafka-min' do
  gem 'karafka', '= 2.3.0'
end

appraise 'relational_db' do
  gem 'activerecord', '~> 7'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'makara', '>= 0.6.0.pre' # Ruby 3 requires >= 0.6.0, which is currently in pre-release: https://rubygems.org/gems/makara/versions
  gem 'mysql2', '>= 0.5.3', platform: :ruby
  gem 'pg', platform: :ruby
  gem 'sqlite3', '>= 1.4.2', platform: :ruby
  gem 'sequel'
  gem 'trilogy'
end

appraise 'activesupport' do
  gem 'activesupport', '~> 7'

  gem 'actionpack'
  gem 'actionview'
  gem 'active_model_serializers', '>= 0.10.0'
  gem 'grape'
  gem 'lograge'
  gem 'racecar', '>= 0.3.5'
  gem 'ruby-kafka', '>= 0.7.10'
end

appraise 'contrib' do
  gem 'concurrent-ruby'
  gem 'grpc', '>= 1.38.0', platform: :ruby # Minimum version with Ruby 3.0 support
  gem 'rack-test' # Dev dependencies for testing rack-based code
  gem 'rake', '>= 12.3'
  gem 'resque'
  gem 'roda', '>= 2.0.0'
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq', '~> 7'
  gem 'sneakers', '>= 2.12.0'
  gem 'sucker_punch'
  gem 'que', '>= 1.0.0'
end

[
  '2.3',
  '2.2',
  '2.1',
  '2.0',
  '1.13',
].each do |v|
  appraise "graphql-#{v}" do
    gem 'rails', '~> 6.1.0'
    gem 'graphql', "~> #{v}.0"
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end
end

build_coverage_matrix('redis', [3, 4])
build_coverage_matrix('rack', 1..2, meta: { 'rack-contrib' => nil, 'rack-test' => nil })

[2, 3, 4].each do |n|
  appraise "sinatra-#{n}" do
    gem 'sinatra', "~> #{n}"
    gem 'rack-contrib'
    gem 'rack-test' # Dev dependencies for testing rack-based code
  end
end

appraise 'opentelemetry' do
  gem 'opentelemetry-sdk', '~> 1.1'
end

appraise 'opentelemetry_otlp' do
  gem 'opentelemetry-sdk', '~> 1.1'
  gem 'opentelemetry-exporter-otlp'
end

appraise 'contrib-old' do
  gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0
end

appraise 'core-old' do
  gem 'dogstatsd-ruby', '~> 4'
end
