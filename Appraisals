lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

def self.gem_cucumber(version)
  appraise "cucumber#{version}" do
    gem 'cucumber', ">=#{version}.0.0", "<#{version + 1}.0.0"
  end
end

if Gem::Version.new(RUBY_VERSION) < Gem::Version.new(Datadog::VERSION::MINIMUM_RUBY_VERSION)
  raise NotImplementedError, "Ruby versions < #{Datadog::VERSION::MINIMUM_RUBY_VERSION} are not supported!"
elsif Gem::Version.new('2.1.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', '0.0.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '>= 1.3.5'
      gem 'makara', '>= 0.3.5', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
    end

    appraise 'rails32-postgres' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'redis-rails', '3.2.4'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.11.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis-rails', '5.0.2'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'contrib-old' do
      gem 'active_model_serializers', '~> 0.9.0'
      gem 'activerecord', '3.2.22.5'
      gem 'activerecord-mysql-adapter', '0.0.1', platform: :ruby
      gem 'aws-sdk', '~> 2.0'
      gem 'concurrent-ruby', '>= 0.9'
      gem 'dalli', '>= 2.0'
      gem 'delayed_job', '>= 4.1'
      gem 'delayed_job_active_record', '>= 4.1'
      gem 'elasticsearch-transport', '>= 1.0'
      gem 'presto-client', '>= 0.5.14'
      gem 'ethon', '>= 0.11'
      gem 'excon', '>= 0.50'
      gem 'hiredis', '>= 0.6.3'
      gem 'http', '>= 2.0'
      gem 'httpclient', '>= 2.2'
      gem 'makara', '>= 0.3.5', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
      gem 'mongo', '>= 2.4.3', '< 2.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'rack', '1.4.7'
      gem 'rack-cache', '1.7.1'
      gem 'rack-test', '0.7.0'
      gem 'rake', '12.2.1'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rest-client', '>= 1.8'
      gem 'resque', '>= 1.0', '< 2.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '~> 4.0', '< 4.37'
      gem 'shoryuken', '>= 3.2'
      gem 'sidekiq', '~> 3.5.4'
      gem 'sinatra', '1.4.5'
      gem 'sqlite3', '>= 1.3.6'
      gem 'sucker_punch', '>= 2.0'
      gem 'timers', '>= 4.1.2', '< 4.2'
      gem 'typhoeus', '>= 1.4.0'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
  end
elsif Gem::Version.new('2.2.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', '0.0.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '>= 1.3.5'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'redis-rails', '3.2.4'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.11.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis-rails', '5.0.2'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '4.2.11.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '5.2.3'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
      gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
    end

    appraise 'rails5-postgres' do
      gem 'rails', '5.2.3'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
      gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '5.2.3'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
      gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '5.2.3'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
      gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '5.2.3'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '>= 5.2.3'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
      gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
    end

    appraise 'contrib' do
      gem 'actionpack', '>= 3.0', '< 5.1.5'
      gem 'actionview', '>= 3.0', '< 5.1.5'
      gem 'active_model_serializers', '>= 0.9'
      gem 'activerecord', '>= 3.0', '< 5.1.5'
      gem 'aws-sdk', '>= 2.0'
      gem 'concurrent-ruby', '>= 0.9'
      gem 'dalli', '>= 2.0'
      gem 'delayed_job', '>= 4.1'
      gem 'delayed_job_active_record', '>= 4.1'
      gem 'elasticsearch-transport', '>= 1.0'
      gem 'pg', '>= 1.2.3', platform: :ruby
      gem 'presto-client', '>= 0.5.14'
      gem 'ethon', '>= 0.11'
      gem 'excon', '>= 0.50'
      gem 'faraday', '>= 0.14'
      gem 'grape', '>= 1.0'
      gem 'graphql', '>= 1.12.0'
      gem 'grpc', '~> 1.19.0' # Last version to support Ruby < 2.3 & google-protobuf < 3.7
      gem 'hiredis', '>= 0.6.3'
      gem 'http', '>= 2.0'
      gem 'httpclient', '>= 2.2'
      gem 'lograge', '>= 0.11'
      gem 'makara', '>= 0.3.5', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '>= 0.3.21', '< 0.5', platform: :ruby
      gem 'qless', '>= 0.10.0'
      gem 'racecar', '>= 0.3.5'
      gem 'rack', '>= 1.1', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
      gem 'rack-test', '>= 1.1.0'
      gem 'rake', '>= 12.3'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rest-client', '>= 1.8'
      gem 'resque', '>= 1.0', '< 2.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '>= 3.41'
      gem 'shoryuken', '>= 3.2'
      gem 'sidekiq', '>= 3.5.4'
      gem 'sinatra', '>= 1.4'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '>= 1.3.6'
      gem 'sucker_punch', '>= 2.0'
      gem 'typhoeus', '>= 1.4.0'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
  end
elsif Gem::Version.new('2.3.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails30-postgres' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails30-postgres-sidekiq' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.0.20'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-mysql2' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'mysql2', '0.3.21', platform: :ruby
      gem 'activerecord-mysql-adapter', '0.0.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
      gem 'sqlite3', '>= 1.3.5'
    end

    appraise 'rails32-postgres' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-redis' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'redis-rails', '3.2.4'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails32-postgres-sidekiq' do
      gem 'test-unit', '3.4.4'
      gem 'rails', '3.2.22.5'
      gem 'pg', '0.15.1', platform: :ruby
      gem 'sidekiq', '4.0.0'
      gem 'rack-cache', '1.7.1'
    end

    appraise 'rails4-mysql2' do
      gem 'rails', '4.2.11.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres-redis' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis-rails', '5.0.2'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails4-postgres-sidekiq' do
      gem 'rails', '4.2.11.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '4.2.11.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '>= 5.2.3'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..4).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack', '>= 3.0', '< 5.1.5'
      gem 'actionview', '>= 3.0', '< 5.1.5'
      gem 'active_model_serializers', '>= 0.9'
      gem 'activerecord', '>= 3.0', '< 5.1.5'
      gem 'aws-sdk', '>= 2.0'
      gem 'concurrent-ruby', '>= 0.9'
      gem 'dalli', '>= 2.0'
      gem 'delayed_job', '>= 4.1'
      gem 'delayed_job_active_record', '>= 4.1'
      gem 'elasticsearch-transport', '>= 1.0'
      gem 'ethon', '>= 0.11'
      gem 'excon', '>= 0.50'
      gem 'faraday', '>= 0.14'
      gem 'grape', '>= 1.0'
      gem 'graphql', '>= 1.12.0'
      gem 'grpc', '>= 1.7'
      gem 'google-protobuf', '~> 3.11.0' # Last version to support Ruby < 2.5
      gem 'hiredis', '>= 0.6.3'
      gem 'http', '>= 2.0'
      gem 'httpclient', '>= 2.2'
      gem 'lograge', '>= 0.11'
      gem 'makara', '>= 0.3.5'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '>= 0.3.21', '< 0.5', platform: :ruby
      gem 'pg', '>= 1.2.3', platform: :ruby
      gem 'presto-client', '>= 0.5.14'
      gem 'qless', '>= 0.10.0'
      gem 'racecar', '>= 0.3.5'
      gem 'rack', '>= 1.1', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
      gem 'rack-test', '>= 1.1.0'
      gem 'rake', '>= 12.3'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rest-client', '>= 1.8'
      gem 'resque', '>= 1.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '>= 3.41'
      gem 'shoryuken', '>= 3.2'
      gem 'sidekiq', '>= 3.5.4'
      gem 'sinatra', '>= 1.4'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '>= 1.3.6'
      gem 'sucker_punch', '>= 2.0'
      gem 'typhoeus', '>= 1.4.0'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
  end
elsif Gem::Version.new('2.4.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '>= 5.2.3'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..4).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack', '>= 4.2.8', '< 5.1.5'
      gem 'actionview', '>= 4.2.8', '< 5.1.5'
      gem 'active_model_serializers', '>= 0.9'
      gem 'activerecord', '>= 4.2.8', '< 5.1.5'
      gem 'aws-sdk', '>= 2.0'
      gem 'concurrent-ruby', '>= 0.9'
      gem 'cucumber', '>= 3.0'
      gem 'dalli', '>= 2.0'
      gem 'delayed_job', '>= 4.1'
      gem 'delayed_job_active_record', '>= 4.1'
      gem 'elasticsearch-transport', '>= 1.0'
      gem 'ethon', '>= 0.11'
      gem 'excon', '>= 0.50'
      gem 'faraday', '>= 0.14'
      gem 'grape', '>= 1.0'
      gem 'graphql', '>= 1.12.0'
      gem 'grpc', '>= 1.7'
      gem 'google-protobuf', '~> 3.11.0' # Last version to support Ruby < 2.5
      gem 'hiredis', '>= 0.6.3'
      gem 'http', '>= 2.0'
      gem 'httpclient', '>= 2.2'
      gem 'lograge', '>= 0.11'
      gem 'makara', '>= 0.3.5'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '>= 0.3.21', '< 0.5', platform: :ruby
      gem 'pg', '>= 1.2.3', platform: :ruby
      gem 'presto-client', '>= 0.5.14'
      gem 'qless', '>= 0.10.0'
      gem 'racecar', '>= 0.3.5', '< 2.3.0' # Locked until https://github.com/zendesk/racecar/issues/252 is addressed
      gem 'rack', '>= 1.1'
      gem 'rack-test', '>= 1.1.0'
      gem 'rake', '>= 12.3'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rest-client', '>= 1.8'
      gem 'resque', '>= 1.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '>= 3.41'
      gem 'shoryuken', '>= 3.2'
      gem 'sidekiq', '>= 3.5.4'
      gem 'sinatra', '>= 1.4'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '>= 1.3.6'
      gem 'sucker_punch', '>= 2.0'
      gem 'typhoeus', '>= 1.4.0'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
  end
elsif Gem::Version.new('2.5.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.6.0')
  appraise 'rails5-mysql2' do
    gem 'rails', '~> 5.2.1'
    gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-postgres' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '52.7', platform: :jruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-postgres-redis' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '52.7', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-postgres-redis-activesupport' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '52.7', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-postgres-sidekiq' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '52.7', platform: :jruby
    gem 'sidekiq', '>= 3.5.4'
    gem 'activejob', '>= 5.2.3'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-mysql2' do
    gem 'rails', '~> 6.0.0'
    gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 60', platform: :jruby # try remove >= 60
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-postgres' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-postgres-redis' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-postgres-redis-activesupport' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-postgres-sidekiq' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sidekiq', '>= 3.5.4'
    gem 'activejob', '~> 6.0.4'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-mysql2' do
    gem 'rails', '~> 6.1.0'
    gem 'mysql2', '~> 0.5', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-postgres' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-postgres-redis' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'redis', '>= 4.2.5'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-postgres-sidekiq' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sidekiq', '>= 6.1.2'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'resque2-redis3' do
    gem 'redis', '>= 3.2', '< 4.0'
    gem 'resque', '>= 2.0'
  end

  appraise 'resque2-redis4' do
    gem 'redis', '>= 4.0'
    gem 'resque', '>= 2.0'
  end

  (3..5).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack', '>= 4.2.8'
    gem 'actionview', '>= 4.2.8'
    gem 'active_model_serializers', '>= 0.9'
    gem 'actionview', '>= 4.2.8'
    gem 'aws-sdk', '>= 2.0'
    gem 'concurrent-ruby', '>= 0.9'
    gem 'cucumber', '>= 3.0'
    gem 'dalli', '>= 2.0'
    gem 'delayed_job', '>= 4.1'
    gem 'delayed_job_active_record', '>= 4.1'
    gem 'elasticsearch-transport', '>= 1.0'
    gem 'ethon', '>= 0.11'
    gem 'excon', '>= 0.50'
    gem 'faraday', '>= 0.14'
    gem 'grape', '>= 1.0'
    gem 'graphql', '>= 1.12.0'
    gem 'grpc', platform: :ruby
    gem 'hiredis', '>= 0.6.3'
    gem 'http', '>= 2.0'
    gem 'httpclient', '>= 2.2'
    gem 'lograge', '>= 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'makara', '>= 0.3.5'
    gem 'mongo', '>= 2.8.0'
    gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 60.2', platform: :jruby
    gem 'pg', '>= 1.2.3', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60.2', platform: :jruby
    gem 'presto-client', '>= 0.5.14'
    gem 'qless', (RUBY_PLATFORM == 'java' ? '0.10.0' : '>= 0.10.0') # Newer releases require `rusage`, which is not available for JRuby
    gem 'racecar', '>= 0.3.5'
    gem 'rack', '>= 1.1'
    gem 'rack-test', '>= 1.1.0'
    gem 'rake', '>= 12.3'
    gem 'redis', '>= 3.2', '< 4.0'
    gem 'rest-client', '>= 1.8'
    gem 'resque', '>= 1.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'sequel', '>= 3.41'
    gem 'shoryuken', '>= 3.2'
    gem 'sidekiq', '>= 3.5.4'
    gem 'sinatra', '>= 1.4'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '>= 1.4.1', platform: :ruby
    gem 'jdbc-sqlite3', '>= 3.28', platform: :jruby
    gem 'sucker_punch', '>= 2.0'
    gem 'typhoeus', '>= 1.4.0'
    gem 'que', '>= 1.0.0.beta2'
  end

  appraise 'contrib-old' do
    gem 'faraday', '0.17'
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
elsif Gem::Version.new('2.6.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '>= 5.2.3'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-mysql2' do
      gem 'rails', '~> 6.0.0'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres-redis' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres-redis-activesupport' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis', '>= 4.0.1'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres-sidekiq' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '~> 6.0.4'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-mysql2' do
      gem 'rails', '~> 6.1.0'
      gem 'mysql2', '~> 0.5', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-postgres' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-postgres-redis' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'redis', '>= 4.2.5'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-postgres-sidekiq' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'sidekiq', '>= 6.1.2'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..5).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack', '>= 5'
      gem 'actionview', '>= 5'
      gem 'active_model_serializers', '>= 0.9'
      gem 'activerecord', '>= 5'
      gem 'aws-sdk', '>= 2.0'
      gem 'concurrent-ruby', '>= 0.9'
      gem 'cucumber', '>= 3.0'
      gem 'dalli', '>= 2.0'
      gem 'delayed_job', '>= 4.1'
      gem 'delayed_job_active_record', '>= 4.1'
      gem 'elasticsearch-transport', '>= 1.0'
      gem 'ethon', '>= 0.11'
      gem 'excon', '>= 0.50'
      gem 'faraday', '>= 0.14'
      gem 'grape', '>= 1.0'
      gem 'graphql', '>= 1.12.0'
      gem 'grpc', '>= 1.7'
      gem 'hiredis', '>= 0.6.3'
      gem 'http', '>= 2.0'
      gem 'httpclient', '>= 2.2'
      gem 'lograge', '>= 0.11'
      gem 'makara', '>= 0.3.5'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'pg', '>= 1.2.3', platform: :ruby
      gem 'presto-client', '>= 0.5.14'
      gem 'qless', '>= 0.10.0'
      gem 'racecar', '>= 0.3.5'
      gem 'rack', '>= 1.1'
      gem 'rack-test', '>= 1.1.0'
      gem 'rake', '>= 12.0'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rest-client', '>= 1.8'
      gem 'resque', '>= 1.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '>= 3.41'
      gem 'shoryuken', '>= 3.2'
      gem 'sidekiq', '>= 3.5.4'
      gem 'sinatra', '>= 1.4'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '>= 1.4.1'
      gem 'sucker_punch', '>= 2.0'
      gem 'typhoeus', '>= 1.4.0'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
  end
elsif Gem::Version.new('2.7.0') <= Gem::Version.new(RUBY_VERSION) \
      && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.0.0')
  if RUBY_PLATFORM != 'java'
    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'makara', '>= 0.3.5', '< 0.5.0'
      gem 'redis', '>= 3.2'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis-rails', '5.0.2'
      gem 'redis', '>= 3.2'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '>= 5.2.3'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-mysql2' do
      gem 'rails', '~> 6.0.0'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres-redis' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis-rails', '5.0.2'
      gem 'redis', '>= 3.2'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres-redis-activesupport' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'redis-rails', '5.0.2'
      gem 'redis', '>= 3.2'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails6-postgres-sidekiq' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '>= 0.21', '< 1.0', platform: :ruby
      gem 'sidekiq', '>= 3.5.4'
      gem 'activejob', '~> 6.0.4'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-mysql2' do
      gem 'rails', '~> 6.1.0'
      gem 'mysql2', '~> 0.5', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-postgres' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-postgres-redis' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'redis', '>= 4.2.5'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'rails61-postgres-sidekiq' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'sidekiq', '>= 6.1.2'
      gem 'sprockets', '>= 3.7.2', '< 4'
      gem 'lograge', '>= 0.11'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '>= 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..5).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack', '>= 5'
      gem 'actionview', '>= 5'
      gem 'active_model_serializers', '>= 0.9'
      gem 'actionview', '>= 5'
      gem 'aws-sdk', '>= 2.0'
      gem 'concurrent-ruby', '>= 0.9'
      gem 'cucumber', '>= 3.0'
      gem 'dalli', '>= 2.0'
      gem 'delayed_job', '>= 4.1'
      gem 'delayed_job_active_record', '>= 4.1'
      gem 'elasticsearch-transport', '>= 1.0'
      gem 'ethon', '>= 0.11'
      gem 'excon', '>= 0.50'
      gem 'grape', '>= 1.0'
      gem 'graphql', '>= 1.12.0'
      gem 'grpc', '>= 1.7'
      gem 'hiredis', '>= 0.6.3'
      gem 'http', '>= 2.0'
      gem 'httpclient', '>= 2.2'
      gem 'lograge', '>= 0.11'
      gem 'makara', '>= 0.3.5'
      gem 'mongo', '>= 2.8.0'
      gem 'mysql2', '>= 0.3.21', '< 1', platform: :ruby
      gem 'pg', '>= 1.2.3', platform: :ruby
      gem 'presto-client', '>= 0.5.14'
      gem 'qless', '>= 0.10.0'
      gem 'racecar', '>= 0.3.5'
      gem 'rack', '>= 1.1'
      gem 'rack-test', '>= 1.1.0'
      gem 'rake', '>= 12.3'
      gem 'redis', '>= 3.2', '< 4.0'
      gem 'rest-client', '>= 1.8'
      gem 'resque', '>= 1.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '>= 3.41'
      gem 'shoryuken', '>= 3.2'
      gem 'sidekiq', '>= 3.5.4'
      gem 'sinatra', '>= 1.4'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '>= 1.4.1'
      gem 'sucker_punch', '>= 2.0'
      gem 'typhoeus', '>= 1.4.0'
      gem 'que', '>= 1.0.0.beta2'
    end

    appraise 'contrib-old' do
      gem 'faraday', '0.17'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
  end
elsif Gem::Version.new('3.0.0') <= Gem::Version.new(RUBY_VERSION)
  appraise 'rails61-mysql2' do
    gem 'rails', '~> 6.1.0'
    gem 'mysql2', '~> 0.5', platform: :ruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
  end

  appraise 'rails61-postgres' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
  end

  appraise 'rails61-postgres-redis' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'redis', '>= 4.2.5'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
  end

  appraise 'rails61-postgres-sidekiq' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'sidekiq', '>= 6.1.2'
    gem 'sprockets', '>= 3.7.2', '< 4'
    gem 'lograge', '>= 0.11'
  end

  appraise 'resque2-redis3' do
    gem 'redis', '>= 3.2', '< 4.0'
    gem 'resque', '>= 2.0'
  end

  appraise 'resque2-redis4' do
    gem 'redis', '>= 4.0'
    gem 'resque', '>= 2.0'
  end

  (3..5).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack', '>= 6.1'
    gem 'actionview', '>= 6.1'
    gem 'active_model_serializers', '>= 0.9'
    gem 'actionview', '>= 6.1'
    gem 'aws-sdk', '>= 2.0'
    gem 'concurrent-ruby', '>= 0.9'
    gem 'cucumber', '>= 3.0'
    gem 'dalli', '>= 2.0'
    gem 'delayed_job', '>= 4.1'
    gem 'delayed_job_active_record', '>= 4.1'
    gem 'elasticsearch-transport', '>= 1.0'
    gem 'ethon', '>= 0.11'
    gem 'excon', '>= 0.50'
    gem 'grape', '>= 1.0'
    gem 'graphql', '>= 1.12.0'
    gem 'grpc', '>= 1.38.0' # Minimum version with Ruby 3.0 support
    gem 'hiredis', '>= 0.6.3'
    gem 'http', '>= 2.0'
    gem 'httpclient', '>= 2.2'
    # gem 'lograge', '>= 0.11'  # creates conflict with qless dependancy on thor ~0.19.1
    gem 'makara', '>= 0.6.0.pre' # Ruby 3 requires >= 0.6.0, which is currently in pre-release: https://rubygems.org/gems/makara/versions
    gem 'mongo', '>= 2.8.0'
    gem 'mysql2', '>= 0.5.3', platform: :ruby
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'presto-client', '>= 0.5.14'
    gem 'qless', '>= 0.10.0'
    # gem 'racecar', '>= 0.3.5' # Pending release of our fix: https://github.com/appsignal/rdkafka-ruby/pull/144
    gem 'rack', '>= 1.1'
    gem 'rack-test', '>= 1.1.0'
    gem 'rake', '>= 12.3'
    gem 'redis', '>= 3.2', '< 4.0'
    gem 'rest-client', '>= 1.8'
    gem 'resque', '>= 1.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'sequel', '>= 3.41'
    gem 'shoryuken', '>= 3.2'
    gem 'sidekiq', '>= 3.5.4'
    gem 'sinatra', '>= 1.4'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '>= 1.4.2'
    gem 'sucker_punch', '>= 2.0'
    gem 'typhoeus', '>= 1.4.0'
    gem 'que', '>= 1.0.0.beta2'
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
end

ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
                 "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
               else
                 "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
               end

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end
