appraise 'hanami-1' do
  gem 'rack'
  gem 'rack-test' # Dev dependencies for testing rack-based code
  gem 'hanami', '~> 1'
end

appraise 'rails5-mysql2' do
  gem 'rails', '~> 5.2.1'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-postgres' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-semantic-logger' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
end

appraise 'rails5-postgres-redis' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails5-postgres-redis-activesupport' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'redis-rails'
  gem 'redis-store', '>= 1.4', '< 2'
end

appraise 'rails5-postgres-sidekiq' do
  gem 'rails', '~> 5.2.1'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq', '~> 6'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-mysql2' do
  gem 'rails', '~> 6.0.0'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-postgres' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-semantic-logger' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
end

appraise 'rails6-postgres-redis' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails6-postgres-redis-activesupport' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'redis-rails'
  gem 'redis-store', '>= 1.4', '< 2'
end

appraise 'rails6-postgres-sidekiq' do
  gem 'rails', '~> 6.0.0'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq', '~> 6'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-mysql2' do
  gem 'rails', '~> 6.1.0'
  gem 'mysql2', '~> 0.5', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-postgres' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-postgres-redis' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'redis', '~> 4'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-postgres-sidekiq' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sidekiq', '>= 6.1.2'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
end

appraise 'rails61-semantic-logger' do
  gem 'rails', '~> 6.1.0'
  gem 'pg', '>= 1.1', platform: :ruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
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
  gem 'redis', '~> 4.0'
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
build_coverage_matrix('faraday', min: '0.14.0')
build_coverage_matrix('excon')
build_coverage_matrix('rest-client')
build_coverage_matrix('mongo', min: '2.1.0')
build_coverage_matrix('dalli', [2])
build_coverage_matrix('devise', min: '3.2.1')

appraise 'relational_db' do
  gem 'activerecord', '~> 6.1.0'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'makara'
  gem 'mysql2', '< 1', platform: :ruby
  gem 'pg', '>= 0.18.4', platform: :ruby
  gem 'sequel'
  gem 'sqlite3', '~> 1.4.1'
end

appraise 'activesupport' do
  gem 'activesupport', '~> 6.1.0'

  gem 'actionpack'
  gem 'actionview'
  gem 'active_model_serializers', '>= 0.10.0'
  gem 'grape'
  gem 'lograge', '~> 0.11'
  gem 'racecar', '>= 0.3.5'
  gem 'ruby-kafka', '>= 0.7.10'
end

appraise 'contrib' do
  gem 'concurrent-ruby'
  gem 'grpc'
  gem 'rack-test' # Dev dependencies for testing rack-based code
  gem 'rake', '>= 12.3'
  gem 'resque'
  gem 'roda', '>= 2.0.0'
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq', '~> 6'
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

# Sinatra 4 requires Ruby (>= 2.7.8), but current image with Ruby 2.7.6
[2, 3].each do |n|
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
