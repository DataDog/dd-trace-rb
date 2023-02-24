lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

module DisableBundleCheck
  def check_command
    ['bundle', 'exec', 'false']
  end
end

if ['true', 'y', 'yes', '1'].include?(ENV['APPRAISAL_SKIP_BUNDLE_CHECK'])
  ::Appraisal::Appraisal.prepend(DisableBundleCheck)
end

def ruby_version?(version)
  full_version = "#{version}.0" # Turn 2.1 into 2.1.0 otherwise #bump below doesn't work as expected

  Gem::Version.new(full_version) <= Gem::Version.new(RUBY_VERSION) &&
    Gem::Version.new(RUBY_VERSION) < Gem::Version.new(full_version).bump
end

alias original_appraise appraise

REMOVED_GEMS = {
  :check => [
    'rbs',
    'steep',
  ],
}

def appraise(group, &block)
  # Specify the environment variable APPRAISAL_GROUP to load only a specific appraisal group.
  if ENV['APPRAISAL_GROUP'].nil? || ENV['APPRAISAL_GROUP'] == group
    original_appraise(group) do
      instance_exec(&block)

      REMOVED_GEMS.each do |group_name, gems|
        group(group_name) do
          gems.each do |gem_name|
            # appraisal 2.2 doesn't have remove_gem, which applies to ruby 2.1 and 2.2
            remove_gem gem_name if respond_to?(:remove_gem)
          end
        end
      end
    end
  end
end

def self.gem_cucumber(version)
  appraise "cucumber#{version}" do
    gem 'cucumber', "~>#{version}"
    # Locks the profiler's protobuf dependency to avoid conflict with cucumber.
    # Without this, we can get this error:
    # > TypeError:
    # >   superclass mismatch for class FileDescriptorSet
    # This happens because cucumber has its own Protobuf gem (`protobuf-cucumber`)
    # that conflicts with `google-protobuf`: the load slightly different version of the same classes.
    # Locking them together ensures they don't have conflicting class declaration.
    # This only affects: 4.0.0 >= cucumber > 7.0.0.
    #
    # DEV: Ideally, the profiler would not be loaded when running cucumber tests as it is unrelated.
    if Gem::Version.new(version) >= Gem::Version.new('4.0.0') &&
      Gem::Version.new(version) < Gem::Version.new('7.0.0')
      gem 'google-protobuf', '3.10.1' if RUBY_PLATFORM != 'java'
      gem 'protobuf-cucumber', '3.10.8'
    end
  end
end

if ruby_version?('2.1')
  appraise 'rails32-mysql2' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'mysql2', '0.3.21'
    gem 'activerecord-mysql-adapter'
    gem 'rack-cache', '1.7.1'
    gem 'sqlite3', '~> 1.3.5'
    gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
  end

  appraise 'rails32-postgres' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails32-postgres-redis' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'redis-rails'
    gem 'redis', '< 4.0'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails32-postgres-sidekiq' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'sidekiq', '4.0.0'
    gem 'rack-cache', '1.7.1'
    gem 'connection_pool', '2.2.3'
  end

  appraise 'rails4-mysql2' do
    gem 'rails', '4.2.11.1'
    gem 'mysql2', '< 1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-postgres' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-semantic-logger' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
  end

  appraise 'rails4-postgres-redis' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'redis-rails'
    gem 'redis', '< 4.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'contrib' do
    gem 'active_model_serializers', '~> 0.9.0'
    gem 'activerecord', '3.2.22.5'
    gem 'activerecord-mysql-adapter'
    gem 'aws-sdk', '~> 2.0'
    gem 'concurrent-ruby'
    gem 'dalli', '< 3.0.0' # Dalli 3.0 dropped support for Ruby < 2.5
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'elasticsearch'
    gem 'presto-client', '>=  0.5.14'
    gem 'multipart-post', '~> 2.1.1' # Compatible with faraday 0.x
    gem 'ethon'
    gem 'excon'
    gem 'http'
    gem 'httpclient'
    gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
    gem 'mongo', '< 2.5'
    gem 'mysql2', '0.3.21'
    gem 'pg', '>= 0.18.4', '< 1.0'
    gem 'rack', '1.4.7'
    gem 'rack-contrib'
    gem 'rack-cache', '1.7.1'
    gem 'rack-test', '0.7.0'
    gem 'rake', '< 12.3'
    gem 'rest-client'
    gem 'resque', '< 2.0'
    gem 'roda', '>= 2.0.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'semantic_logger', '~> 4.0'
    gem 'sequel', '~> 4.0', '< 4.37'
    gem 'shoryuken'
    gem 'sidekiq', '~> 3.5.4'
    gem 'sqlite3', '~> 1.3.6'
    gem 'sucker_punch'
    gem 'timers', '< 4.2'
    gem 'typhoeus'
  end

  appraise 'sinatra' do
    gem 'sinatra'
    gem 'rack-test'
  end

  [3].each do |n|
    appraise "redis-#{n}" do
      gem 'redis', "~> #{n}"
    end
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('2.2')
  appraise 'rails32-mysql2' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'mysql2', '0.3.21'
    gem 'activerecord-mysql-adapter'
    gem 'rack-cache', '1.7.1'
    gem 'sqlite3', '~> 1.3.5'
  end

  appraise 'rails32-postgres' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails32-postgres-redis' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'redis-rails'
    gem 'redis', '< 4.0'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails32-postgres-sidekiq' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'sidekiq', '4.0.0'
    gem 'rack-cache', '1.7.1'
    gem 'connection_pool', '2.2.3'
  end

  appraise 'rails4-mysql2' do
    gem 'rails', '4.2.11.1'
    gem 'mysql2', '< 1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-postgres' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-semantic-logger' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
  end

  appraise 'rails4-postgres-redis' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'redis-rails'
    gem 'redis', '< 4.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-postgres-sidekiq' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sidekiq'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-mysql2' do
    gem 'rails', '5.2.3'
    gem 'mysql2', '< 1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
  end

  appraise 'rails5-postgres' do
    gem 'rails', '5.2.3'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
  end

  appraise 'rails5-postgres-redis' do
    gem 'rails', '5.2.3'
    gem 'pg', '< 1.0'
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
  end

  appraise 'rails5-postgres-redis-activesupport' do
    gem 'rails', '5.2.3'
    gem 'pg', '< 1.0'
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
    gem 'redis-rails'
  end

  appraise 'rails5-postgres-sidekiq' do
    gem 'rails', '5.2.3'
    gem 'pg', '< 1.0'
    gem 'sidekiq', '~> 5.0'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
  end

  appraise 'rails5-semantic-logger' do
    gem 'rails', '5.2.3'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
    gem 'mimemagic', '0.3.9' # Pinned until https://github.com/mimemagicrb/mimemagic/issues/142 is resolved.
  end

  appraise 'contrib' do
    gem 'actionpack'
    gem 'actionview'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord', '< 5.1.5'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'dalli', '< 3.0.0' # Dalli 3.0 dropped support for Ruby < 2.5
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'elasticsearch'
    gem 'ethon'
    gem 'excon'
    gem 'faraday'
    gem 'multipart-post', '~> 2.1.1' # Compatible with faraday 0.x
    gem 'grape'
    gem 'graphql'
    gem 'grpc', '~> 1.19.0' # Last version to support Ruby < 2.3 & google-protobuf < 3.7
    gem 'http'
    gem 'httpclient'
    gem 'lograge', '~> 0.11'
    gem 'makara', '< 0.5.0' # >= 0.5.0 contain Ruby 2.3+ syntax
    gem 'mongo', '>= 2.8.0'
    gem 'mysql2', '< 0.5'
    gem 'pg', '>= 0.18.4'
    gem 'presto-client', '>=  0.5.14'
    gem 'racecar', '>= 0.3.5'
    gem 'rack', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
    gem 'rack-contrib'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'rest-client'
    gem 'resque', '< 2.0'
    gem 'roda', '>= 2.0.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'semantic_logger', '~> 4.0'
    gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
    gem 'shoryuken'
    gem 'sidekiq'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '~> 1.3.6'
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0', '< 2.0.0'
  end

  appraise 'sinatra' do
    gem 'sinatra'
    gem 'rack-test'
  end

  [3].each do |n|
    appraise "redis-#{n}" do
      gem 'redis', "~> #{n}"
    end
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('2.3')
  appraise 'hanami-1' do
    gem 'rack'
    gem 'rack-test'
    gem 'hanami', '~> 1'
  end

  appraise 'rails32-mysql2' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'mysql2', '0.3.21'
    gem 'activerecord-mysql-adapter'
    gem 'rack-cache', '1.7.1'
    gem 'sqlite3', '~> 1.3.5'
  end

  appraise 'rails32-postgres' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails32-postgres-redis' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'redis-rails'
    gem 'redis', '< 4.0'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails32-postgres-sidekiq' do
    gem 'test-unit'
    gem 'rails', '3.2.22.5'
    gem 'pg', '0.15.1'
    gem 'sidekiq', '4.0.0'
    gem 'rack-cache', '1.7.1'
  end

  appraise 'rails4-mysql2' do
    gem 'rails', '4.2.11.1'
    gem 'mysql2', '< 1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-postgres' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-semantic-logger' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
  end

  appraise 'rails4-postgres-redis' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'redis-rails'
    gem 'redis', '< 4.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails4-postgres-sidekiq' do
    gem 'rails', '4.2.11.1'
    gem 'pg', '< 1.0'
    gem 'sidekiq'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-mysql2' do
    gem 'rails', '~> 5.2.1'
    gem 'mysql2', '< 1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-postgres' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-postgres-redis' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-semantic-logger' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
  end

  appraise 'rails5-postgres-redis-activesupport' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'redis-rails'
    gem 'redis-store', '> 1.6.0'
  end

  appraise 'rails5-postgres-sidekiq' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'sidekiq'
    gem 'activejob'
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

  (3..4).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack'
    gem 'actionview'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord', '< 5.1.5'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'dalli', '< 3.0.0' # Dalli 3.0 dropped support for Ruby < 2.5
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'ethon'
    gem 'excon'
    gem 'faraday', '>= 1.0'
    gem 'grape'
    gem 'graphql'
    gem 'grpc'
    gem 'google-protobuf', '~> 3.11.0' # Last version to support Ruby < 2.5
    gem 'http'
    gem 'httpclient'
    gem 'lograge', '~> 0.11'
    gem 'makara'
    gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
    gem 'mysql2', '< 0.5'
    gem 'pg', '>= 0.18.4'
    gem 'racecar', '>= 0.3.5'
    gem 'rack', '< 2.1.0' # Locked due to grape incompatibility: https://github.com/ruby-grape/grape/issues/1980
    gem 'rack-contrib'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'rest-client'
    gem 'resque'
    gem 'roda', '>= 2.0.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'semantic_logger', '~> 4.0'
    gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
    gem 'shoryuken'
    gem 'sidekiq'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '~> 1.3.6'
    gem 'stripe', '~> 5.15'
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0', '< 2.0.0'
  end

  appraise 'sinatra' do
    gem 'sinatra', '< 3.0'
    gem 'mustermann', '< 3.0'
    gem 'rack-test'
  end

  [3].each do |n|
    appraise "redis-#{n}" do
      gem 'redis', "~> #{n}"
    end
  end

  appraise 'contrib-old' do
    gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
    gem 'faraday', '0.17'
    gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('2.4')
  appraise 'hanami-1' do
    gem 'rack'
    gem 'rack-test'
    gem 'hanami', '~> 1'
  end

  appraise 'rails5-mysql2' do
    gem 'rails', '~> 5.2.1'
    gem 'mysql2', '< 1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-postgres' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-semantic-logger' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
  end

  appraise 'rails5-postgres-redis' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end

  appraise 'rails5-postgres-redis-activesupport' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'redis-rails'
  end

  appraise 'rails5-postgres-sidekiq' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0'
    gem 'sidekiq'
    gem 'activejob'
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

  (3..4).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack'
    gem 'actionview'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord', '< 5.1.5'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'cucumber'
    gem 'dalli', '< 3.0.0' # Dalli 3.0 dropped support for Ruby < 2.5
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'ethon'
    gem 'excon'
    gem 'faraday', '>= 1.0'
    gem 'grape'
    gem 'graphql', '>= 2.0'
    gem 'grpc'
    gem 'google-protobuf', '~> 3.11.0' # Last version to support Ruby < 2.5
    gem 'http'
    gem 'httpclient'
    gem 'lograge', '~> 0.11'
    gem 'makara'
    gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
    gem 'mysql2', '< 0.5'
    gem 'pg', '>= 0.18.4'
    gem 'racecar', '>= 0.3.5'
    gem 'rack'
    gem 'rack-contrib'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'rest-client'
    gem 'resque'
    gem 'roda', '>= 2.0.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'semantic_logger', '~> 4.0'
    gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
    gem 'shoryuken'
    gem 'sidekiq'
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '~> 1.3.6'
    gem 'stripe', '~> 6.0'
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0', '< 2.0.0'
  end

  appraise 'sinatra' do
    gem 'sinatra'
    gem 'rack-test'
  end

  [3, 4].each do |n|
    appraise "redis-#{n}" do
      gem 'redis', "~> #{n}"
    end
  end

  appraise 'contrib-old' do
    gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
    gem 'faraday', '0.17'
    gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
    gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('2.5')
  appraise 'hanami-1' do
    gem 'rack'
    gem 'rack-test'
    gem 'hanami', '~> 1'
  end

  appraise 'rails5-mysql2' do
    gem 'rails', '~> 5.2.1'
    gem 'mysql2', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
  end

  appraise 'rails5-postgres' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-semantic-logger' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-postgres-redis' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails5-postgres-redis-activesupport' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'redis'
    gem 'redis-store', '~> 1.9'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'redis-rails'
  end

  appraise 'rails5-postgres-sidekiq' do
    gem 'rails', '~> 5.2.1'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sidekiq'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-mysql2' do
    gem 'rails', '~> 6.0.0'
    gem 'mysql2', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 60', platform: :jruby # try remove >= 60
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
  end

  appraise 'rails6-postgres' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-semantic-logger' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-postgres-redis' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'redis', '>= 4.0.1'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails6-postgres-redis-activesupport' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'redis'
    gem 'redis-store', '~> 1.9'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'redis-rails'
  end

  appraise 'rails6-postgres-sidekiq' do
    gem 'rails', '~> 6.0.0'
    gem 'pg', '< 1.0', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
    gem 'sidekiq'
    gem 'activejob'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-mysql2' do
    gem 'rails', '~> 6.1.0'
    gem 'mysql2', '~> 0.5', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
  end

  appraise 'rails61-postgres' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-postgres-redis' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'redis', '>= 4.2.5'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-postgres-sidekiq' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sidekiq', '>= 6.1.2'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'rails61-semantic-logger' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  end

  appraise 'resque2-redis3' do
    gem 'redis', '< 4.0'
    gem 'resque', '>= 2.0'
  end

  appraise 'resque2-redis4' do
    gem 'redis', '>= 4.0'
    gem 'resque', '>= 2.0'
  end

  (3..5).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack'
    gem 'actionview'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'cucumber'
    gem 'dalli', '>= 3.0.0'
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'elasticsearch', '>= 8.0.0'
    # Workaround bundle of JRuby/ethon issues:
    # * ethon 0.15.0 is incompatible with most JRuby 9.2 versions (fixed in 9.2.20.0),
    #   see https://github.com/typhoeus/ethon/issues/205
    # * we test with 9.2.18.0 because ethon is completely broken on JRuby 9.2.19.0+ WHEN RUN on a Java 8 VM,
    #   see https://github.com/jruby/jruby/issues/7033
    #
    # Thus let's keep our JRuby testing on 9.2.18.0 with Java 8, and avoid pulling in newer ethon versions until
    # either the upstream issues are fixed OR we end up moving to Java 11.
    gem 'ethon', (RUBY_PLATFORM == 'java' ? '< 0.15.0' : '>= 0')
    gem 'excon'
    gem 'faraday', '>= 1.0'
    gem 'grape'
    gem 'graphql', '>= 2.0'
    gem 'grpc', platform: :ruby
    gem 'http'
    gem 'httpclient'
    gem 'lograge', '~> 0.11'
    gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
    gem 'makara'
    gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
    gem 'mysql2', '< 1', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', '>= 60.2', platform: :jruby
    gem 'pg', '>= 0.18.4', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', '>= 60.2', platform: :jruby
    gem 'racecar', '>= 0.3.5'
    gem 'rack'
    gem 'rack-contrib'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'rest-client'
    gem 'resque'
    gem 'roda', '>= 2.0.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'semantic_logger', '~> 4.0'
    gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
    gem 'shoryuken'
    gem 'sidekiq'
    gem 'sneakers', '>= 2.12.0'
    gem 'bunny', '~> 2.19.0' # uninitialized constant OpenSSL::SSL::TLS1_3_VERSION for jruby, https://github.com/ruby-amqp/bunny/issues/645
    gem 'sqlite3', '~> 1.4.1', platform: :ruby
    gem 'stripe', '~> 7.0'
    gem 'jdbc-sqlite3', '>= 3.28', platform: :jruby
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0', '< 2.0.0'
  end

  appraise 'sinatra' do
    gem 'sinatra'
    gem 'rack-test'
  end

  [3, 4, 5].each do |n|
    appraise "redis-#{n}" do
      gem 'redis', "~> #{n}"
    end
  end

  appraise 'contrib-old' do
    gem 'dalli', '< 3.0.0'
    gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
    gem 'faraday', '0.17'
    gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
    gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0

    if RUBY_PLATFORM == 'java'
      gem 'qless', '0.10.0' # Newer releases require `rusage`, which is not available for JRuby
      gem 'redis', '< 4' # Missing redis version cap for `qless`
    else
      gem 'qless', '0.12.0'
    end
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('2.6')
    appraise 'hanami-1' do
      gem 'rack'
      gem 'rack-test'
      gem 'hanami', '~> 1'
    end

    appraise 'rails5-mysql2' do
      gem 'rails', '~> 5.2.1'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails5-postgres' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails5-semantic-logger' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'rails_semantic_logger', '~> 4.0'
    end

    appraise 'rails5-postgres-redis' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis', '~> 4' # TODO: Support redis 5.x
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
      gem 'redis-rails'
      gem 'redis-store', '>= 1.4', '< 2'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails6-mysql2' do
      gem 'rails', '~> 6.0.0'
      gem 'mysql2', '< 1', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails6-postgres' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails6-semantic-logger' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'rails_semantic_logger', '~> 4.0'
    end

    appraise 'rails6-postgres-redis' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis', '~> 4' # TODO: Support redis 5.x
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails6-postgres-redis-activesupport' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
      gem 'redis-rails'
      gem 'redis-store', '>= 1.4', '< 2'
    end

    appraise 'rails6-postgres-sidekiq' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq'
      gem 'activejob'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails61-mysql2' do
      gem 'rails', '~> 6.1.0'
      gem 'mysql2', '~> 0.5', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails61-postgres' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails61-postgres-redis' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'redis', '~> 4' # TODO: Support redis 5.x
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails61-postgres-sidekiq' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sidekiq', '>= 6.1.2'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails61-semantic-logger' do
      gem 'rails', '~> 6.1.0'
      gem 'pg', '>= 1.1', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'sprockets', '< 4'
      gem 'rails_semantic_logger', '~> 4.0'
    end

    appraise 'resque2-redis3' do
      gem 'redis', '~> 3.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '~> 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..5).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'cucumber', '~> 7' # TODO: Support cucumber 8.x
      gem 'dalli', '>= 3.0.0'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch', '>= 8.0.0'
      gem 'ethon'
      gem 'excon'
      gem 'faraday', '>= 1.0'
      gem 'grape'
      gem 'graphql', '>= 2.0'
      gem 'grpc', platform: :ruby
      gem 'http'
      gem 'httpclient'
      gem 'lograge', '~> 0.11'
      gem 'makara'
      gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
      gem 'mysql2', '< 1', platform: :ruby
      gem 'activerecord-jdbcmysql-adapter', platform: :jruby
      gem 'pg', '>= 0.18.4', platform: :ruby
      gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-contrib'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'redis', '~> 4' # TODO: Support redis 5.x
      gem 'rest-client'
      gem 'resque'
      gem 'roda', '>= 2.0.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'semantic_logger', '~> 4.0'
      gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
      gem 'shoryuken'
      gem 'sidekiq', '~> 6.5'
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.4.1', platform: :ruby
      gem 'stripe', '~> 8.0'
      gem 'jdbc-sqlite3', '>= 3.28', platform: :jruby
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0', '< 2.0.0'
    end

    appraise 'sinatra' do
      gem 'sinatra', '>= 3'
      gem 'rack-test'
    end

    appraise 'opentelemetry' do
      gem 'opentelemetry-sdk', '~> 1.1'
    end

    [3, 4, 5].each do |n|
      appraise "redis-#{n}" do
        gem 'redis', "~> #{n}"
      end
    end

    appraise 'contrib-old' do
      gem 'dalli', '< 3.0.0'
      gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
      gem 'faraday', '0.17'
      gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
      gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0

      if RUBY_PLATFORM == 'java'
        gem 'qless', '0.10.0' # Newer releases require `rusage`, which is not available for JRuby
        gem 'redis', '< 4' # Missing redis version cap for `qless`
      else
        gem 'qless', '0.12.0'
      end
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('2.7')
    appraise 'hanami-1' do
      gem 'rack'
      gem 'rack-test'
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
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails5-postgres-redis-activesupport' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
      gem 'redis-rails'
      gem 'redis-store', '>= 1.4', '< 2'
    end

    appraise 'rails5-postgres-sidekiq' do
      gem 'rails', '~> 5.2.1'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
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
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
    end

    appraise 'rails6-postgres-redis-activesupport' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'redis'
      gem 'sprockets', '< 4'
      gem 'lograge', '~> 0.11'
      gem 'redis-rails'
      gem 'redis-store', '>= 1.4', '< 2'
    end

    appraise 'rails6-postgres-sidekiq' do
      gem 'rails', '~> 6.0.0'
      gem 'pg', '< 1.0', platform: :ruby
      gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
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

    appraise 'resque2-redis3' do
      gem 'redis', '< 4.0'
      gem 'resque', '>= 2.0'
    end

    appraise 'resque2-redis4' do
      gem 'redis', '~> 4.0'
      gem 'resque', '>= 2.0'
    end

    (3..5).each { |v| gem_cucumber(v) }

    appraise 'contrib' do
      gem 'actionpack'
      gem 'actionview'
      gem 'active_model_serializers', '>= 0.10.0'
      gem 'activerecord'
      gem 'aws-sdk'
      gem 'concurrent-ruby'
      gem 'cucumber', '~> 7' # TODO: Support cucumber 8.x
      gem 'dalli', '>= 3.0.0'
      gem 'delayed_job'
      gem 'delayed_job_active_record'
      gem 'elasticsearch', '>= 8.0.0'
      gem 'ethon'
      gem 'excon'
      gem 'grape'
      gem 'graphql', '>= 2.0'
      gem 'grpc'
      gem 'http'
      gem 'httpclient'
      gem 'lograge', '~> 0.11'
      gem 'makara'
      gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
      gem 'mysql2', '< 1', platform: :ruby
      gem 'pg', '>= 0.18.4', platform: :ruby
      gem 'racecar', '>= 0.3.5'
      gem 'rack'
      gem 'rack-contrib'
      gem 'rack-test'
      gem 'rake', '>= 12.3'
      gem 'rest-client'
      gem 'resque'
      gem 'roda', '>= 2.0.0'
      gem 'ruby-kafka', '>= 0.7.10'
      gem 'rspec', '>= 3.0.0'
      gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
      gem 'semantic_logger', '~> 4.0'
      gem 'shoryuken'
      gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
      gem 'sneakers', '>= 2.12.0'
      gem 'sqlite3', '~> 1.4.1'
      gem 'stripe'
      gem 'sucker_punch'
      gem 'typhoeus'
      gem 'que', '>= 1.0.0'
    end

    appraise 'sinatra' do
      gem 'sinatra', '>= 3'
      gem 'rack-test'
    end

    appraise 'opentelemetry' do
      gem 'opentelemetry-sdk', '~> 1.1'
    end

    [3, 4, 5].each do |n|
      appraise "redis-#{n}" do
        gem 'redis', "~> #{n}"
      end
    end

    appraise 'contrib-old' do
      gem 'dalli', '< 3.0.0'
      gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
      gem 'faraday', '0.17'
      gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
      gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0
      gem 'qless', '0.12.0'
    end

    appraise 'core-old' do
      gem 'dogstatsd-ruby', '~> 4'
    end
# ----------------------------------------------------------------------------------------------------------------------
elsif ruby_version?('3.0') || ruby_version?('3.1') || ruby_version?('3.2')
  appraise 'rails61-mysql2' do
    gem 'rails', '~> 6.1.0'
    gem 'mysql2', '~> 0.5', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'net-smtp'
  end

  appraise 'rails61-postgres' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'net-smtp'
  end

  appraise 'rails61-postgres-redis' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'redis', '~> 4' # TODO: Support redis 5.x
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'net-smtp'
  end

  appraise 'rails61-postgres-sidekiq' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sidekiq', '>= 6.1.2'
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
    gem 'rails_semantic_logger', '~> 4.0'
    gem 'net-smtp'
  end

  appraise 'rails61-semantic-logger' do
    gem 'rails', '~> 6.1.0'
    gem 'pg', '>= 1.1', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'sprockets', '< 4'
    gem 'rails_semantic_logger', '~> 4.0'
    gem 'net-smtp'
  end

  appraise 'resque2-redis3' do
    gem 'redis', '< 4.0'
    gem 'resque', '>= 2.0'
  end

  appraise 'resque2-redis4' do
    gem 'redis', '>= 4.0'
    gem 'resque', '>= 2.0'
  end

  (3..5).each { |v| gem_cucumber(v) }

  appraise 'contrib' do
    gem 'actionpack', '~> 7'
    gem 'actionview', '~> 7'
    gem 'active_model_serializers', '>= 0.10.0'
    gem 'activerecord', '~> 7'
    gem 'aws-sdk'
    gem 'concurrent-ruby'
    gem 'cucumber', '~> 7' # TODO: Support cucumber 8.x
    gem 'dalli', '>= 3.0.0'
    gem 'delayed_job'
    gem 'delayed_job_active_record'
    gem 'elasticsearch', '>= 8.0.0'
    gem 'ethon'
    gem 'excon'
    gem 'grape'
    gem 'graphql', '>= 2.0'
    gem 'grpc', '>= 1.38.0', platform: :ruby # Minimum version with Ruby 3.0 support
    gem 'http'
    gem 'httpclient'
    gem 'lograge'
    gem 'makara', '>= 0.6.0.pre' # Ruby 3 requires >= 0.6.0, which is currently in pre-release: https://rubygems.org/gems/makara/versions
    gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
    gem 'mysql2', '>= 0.5.3', platform: :ruby
    gem 'activerecord-jdbcmysql-adapter', platform: :jruby
    gem 'pg', platform: :ruby
    gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
    gem 'racecar', '>= 0.3.5'
    gem 'rack'
    gem 'rack-contrib'
    gem 'rack-test'
    gem 'rake', '>= 12.3'
    gem 'rest-client'
    gem 'resque'
    gem 'roda', '>= 2.0.0'
    gem 'ruby-kafka', '>= 0.7.10'
    gem 'rspec', '>= 3.0.0'
    gem 'semantic_logger', '~> 4.0'
    gem 'sequel', '~> 5.54.0' # TODO: Support sequel 5.62.0+
    gem 'shoryuken'
    gem 'sidekiq', '~> 6' # TODO: Support sidekiq 7.x
    gem 'sneakers', '>= 2.12.0'
    gem 'sqlite3', '>= 1.4.2', platform: :ruby
    gem 'stripe'
    gem 'jdbc-sqlite3', '>= 3.28', platform: :jruby
    gem 'sucker_punch'
    gem 'typhoeus'
    gem 'que', '>= 1.0.0'
    gem 'net-smtp'
  end

  [3, 4, 5].each do |n|
    appraise "redis-#{n}" do
      gem 'redis', "~> #{n}"
    end
  end

  appraise 'sinatra' do
    gem 'sinatra', '>= 3'
    gem 'rack-test'
  end

  appraise 'opentelemetry' do
    gem 'opentelemetry-sdk', '~> 1.1'
  end

  appraise 'contrib-old' do
    gem 'dalli', '< 3.0.0'
    gem 'elasticsearch', '< 8.0.0' # Dependency elasticsearch-transport renamed to elastic-transport in >= 8.0
    gem 'graphql', '~> 1.12.0', '< 2.0' # TODO: Support graphql 1.13.x
    gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0

    if RUBY_PLATFORM == 'java'
      gem 'qless', '0.10.0' # Newer releases require `rusage`, which is not available for JRuby
      gem 'redis', '< 4' # Missing redis version cap for `qless`
    else
      gem 'qless', '0.12.0'
    end
  end

  appraise 'core-old' do
    gem 'dogstatsd-ruby', '~> 4'
  end
# ----------------------------------------------------------------------------------------------------------------------
# ADD NEW RUBIES HERE
end

ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
                 "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
               else
                 "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
               end

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end

# vim: ft=ruby
