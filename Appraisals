def ruby_version(version, java_required = false)
  return if java_required && RUBY_PLATFORM != 'java'

  version = Gem::Version.new(version)
  current_version = Gem::Version.new(RUBY_VERSION)

  yield if current_version >= version && current_version < version.bump
end

raise NotImplementedError, 'Ruby versions < 1.9.3 are not supported!' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('1.9.3')

def appr(name, *closures, &block)
  @common_appraisals ||= {}
  @versions ||= {}
  @versions[name] ||= {}
  versions = @versions[name].dup
  common_appraisal = @common_appraisals[name]

  appraise(name) do
    closures.each do |closure|
      instance_exec(versions, &closure)
    end

    instance_exec(versions, &common_appraisal) if common_appraisal
    instance_exec(versions, &block) if block_given?
  end
end

def common_appr(name, &block)
  @common_appraisals ||= {}
  @common_appraisals[name] = block
end

def version(**versions)
  proc do |appraisal_version|
    appraisal_version.merge!(versions)
  end
end

common_appr('rails30-postgres') do
  gem 'test-unit'
  gem 'rails', '3.0.20'
  gem 'pg', '0.15.1', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'rack-cache', '1.7.1'
end

common_appr 'rails30-postgres-sidekiq' do
  gem 'test-unit'
  gem 'rails', '3.0.20'
  gem 'pg', '0.15.1', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'sidekiq', '4.0.0'
  gem 'rack-cache', '1.7.1'
end

common_appr('contrib-old') do
  gem 'active_model_serializers', '~> 0.9.0'
  gem 'activerecord', '3.2.22.5'
  gem 'activerecord-mysql-adapter', platform: :ruby
  gem 'aws-sdk', '~> 2.0'
  gem 'dalli'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'elasticsearch-transport'
  gem 'excon'
  gem 'hiredis'
  gem 'mongo', '< 2.5'
  gem 'mysql2', '0.3.21', platform: :ruby
  gem 'rack', '1.4.7'
  gem 'rack-cache', '1.7.1'
  gem 'rack-test', '0.7.0'
  gem 'rake', '< 12.3'
  gem 'redis', '< 4.0'
  gem 'rest-client', '< 2.0'
  gem 'resque', '< 2.0'
  gem 'sequel', '~> 4.0', '< 4.37'
  gem 'sidekiq', '4.0.0'
  gem 'sinatra', '1.4.5'
  gem 'sqlite3'
  gem 'sucker_punch'
end

common_appr('contrib') do
  gem 'active_model_serializers', '>= 0.10.0'
  gem 'activerecord', '< 5.1.5'
  gem 'aws-sdk'
  gem 'dalli'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'elasticsearch-transport'
  gem 'excon'
  gem 'grape'
  gem 'graphql'
  gem 'grpc'
  gem 'hiredis'
  gem 'mongo', '< 2.5'
  gem 'mysql2', '< 0.5', platform: :ruby
  gem 'racecar', '>= 0.3.5'
  gem 'rack'
  gem 'rack-test'
  gem 'rake', '>= 12.3'
  gem 'redis', '< 4.0'
  gem 'rest-client'
  gem 'resque', '< 2.0'
  gem 'sequel'
  gem 'sidekiq'
  gem 'sinatra'
  gem 'sqlite3'
  gem 'sucker_punch'
end

common_appr 'rails32-mysql2' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'mysql2', '0.3.21', platform: :ruby
  gem 'activerecord-mysql-adapter', platform: :ruby
  gem 'activerecord-jdbcmysql-adapter', platform: :jruby
  gem 'rack-cache', '1.7.1'
end

common_appr 'rails32-postgres' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'pg', '0.15.1', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'rack-cache', '1.7.1'
end

common_appr 'rails32-postgres-redis' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'pg', '0.15.1', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'redis-rails'
  gem 'redis', '< 4.0'
  gem 'rack-cache', '1.7.1'
end

common_appr 'rails32-postgres-sidekiq' do
  gem 'test-unit'
  gem 'rails', '3.2.22.5'
  gem 'pg', '0.15.1', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'sidekiq', '4.0.0'
  gem 'rack-cache', '1.7.1'
end

common_appr 'rails4-mysql2' do |version|
  gem 'rails', version.fetch(:rails, '4.2.7.1')
  gem 'mysql2', '< 0.5', platform: :ruby
  gem 'activerecord-jdbcmysql-adapter', platform: :jruby
end

common_appr 'rails4-postgres' do |version|
  gem 'rails', version.fetch(:rails, '4.2.7.1')
  gem 'pg', '< 1.0', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
end

common_appr 'rails4-postgres-redis' do |version|
  gem 'rails', version.fetch(:rails, '4.2.7.1')
  gem 'pg', '< 1.0', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'redis-rails'
  gem 'redis', '< 4.0'
end

common_appr 'rails4-postgres-sidekiq' do |version|
  gem 'rails', version.fetch(:rails, '4.2.7.1')
  gem 'pg', '< 1.0', platform: :ruby
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'sidekiq'
  gem 'activejob'
end

common_appr 'rails5-mysql2' do
  gem 'rails', '~> 5.1.6'
  gem 'mysql2', '< 0.5', platform: :ruby
end

common_appr 'rails5-postgres' do
  gem 'rails', '~> 5.1.6'
  gem 'pg', '< 1.0', platform: :ruby
end

common_appr 'rails5-postgres-redis' do
  gem 'rails', '~> 5.1.6'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'redis-rails'
  gem 'redis'
end

common_appr 'rails5-postgres-sidekiq' do
  gem 'rails', '~> 5.1.6'
  gem 'pg', '< 1.0', platform: :ruby
  gem 'sidekiq'
  gem 'activejob'
end

ruby_version('1.9.3') do
  rake = proc { gem 'rake', '< 12.3' }

  appr 'rails30-postgres', rake
  appr 'rails30-postgres-sidekiq', rake
  appr 'rails32-mysql2', rake
  appr 'rails32-postgres', rake
  appr 'rails32-postgres-redis', rake
  appr 'rails32-postgres-sidekiq', rake
  appr 'contrib-old', rake
end

ruby_version('2.0.0') do
  appr 'rails30-postgres'
  appr 'rails30-postgres-sidekiq'
  appr 'rails32-mysql2'
  appr 'rails32-postgres'
  appr 'rails32-postgres-redis'
  appr 'rails32-postgres-sidekiq'
  appr 'contrib-old'
end

ruby_version('2.1.0') do
  appr 'rails30-postgres'
  appr 'rails30-postgres-sidekiq'
  appr 'rails32-mysql2'
  appr 'rails32-postgres'
  appr 'rails32-postgres-redis'
  appr 'rails32-postgres-sidekiq'
  appr 'rails4-mysql2'
  appr 'rails4-postgres'
  appr 'rails4-postgres-redis'
  appr 'contrib-old'
end

ruby_version('2.2.0') do
  appr 'rails30-postgres'
  appr 'rails30-postgres-sidekiq'
  appr 'rails32-mysql2'
  appr 'rails32-postgres'
  appr 'rails32-postgres-redis'
  appr 'rails32-postgres-sidekiq'
  appr 'rails4-mysql2'
  appr 'rails4-postgres'
  appr 'rails4-postgres-redis'
  appr 'rails4-postgres-sidekiq'
  appr 'rails5-mysql2'
  appr 'rails5-postgres'
  appr 'rails5-postgres-redis'
  appr 'rails5-postgres-sidekiq'
  appr 'contrib'
end

ruby_version('2.3.0') do
  appr 'rails30-postgres'
  appr 'rails30-postgres-sidekiq'
  appr 'rails32-mysql2'
  appr 'rails32-postgres'
  appr 'rails32-postgres-redis'
  appr 'rails32-postgres-sidekiq'
  appr 'rails4-mysql2'
  appr 'rails4-postgres'
  appr 'rails4-postgres-redis'
  appr 'rails4-postgres-sidekiq'
  appr 'rails5-mysql2'
  appr 'rails5-postgres'
  appr 'rails5-postgres-redis'
  appr 'rails5-postgres-sidekiq'
  appr 'contrib'
end

ruby_version('2.4.0') do
  appr 'rails30-postgres'
  appr 'rails30-postgres-sidekiq'
  appr 'rails32-postgres'
  appr 'rails32-postgres-redis'
  appr 'rails32-postgres-sidekiq'
  appr 'rails4-mysql2'
  appr 'rails4-postgres'
  appr 'rails4-postgres-redis'
  appr 'rails4-postgres-sidekiq'
  appr 'rails5-mysql2'
  appr 'rails5-postgres'
  appr 'rails5-postgres-redis'
  appr 'rails5-postgres-sidekiq'
  appr 'contrib'
end

ruby_version('2.5.0') do
  rails4_version = version(rails: '>= 4.2.8')

  appr 'rails30-postgres'
  appr 'rails30-postgres-sidekiq'
  appr 'rails32-postgres'
  appr 'rails32-postgres-redis'
  appr 'rails32-postgres-sidekiq'
  appr 'rails4-mysql2', rails4_version
  appr 'rails4-postgres', rails4_version
  appr 'rails4-postgres-redis', rails4_version
  appr 'rails4-postgres-sidekiq', rails4_version
  appr 'rails5-mysql2'
  appr 'rails5-postgres'
  appr 'rails5-postgres-redis'
  appr 'rails5-postgres-sidekiq'
  appr 'contrib'
end
