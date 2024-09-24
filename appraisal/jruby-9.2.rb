appraise 'rails5-mysql2' do
  gem 'rails', '~> 5.2.1'
  gem 'activerecord-jdbcmysql-adapter', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
end

appraise 'rails5-postgres' do
  gem 'rails', '~> 5.2.1'
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails5-semantic-logger' do
  gem 'rails', '~> 5.2.1'
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails5-postgres-redis' do
  gem 'rails', '~> 5.2.1'
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'redis', '>= 4.0.1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails5-postgres-redis-activesupport' do
  gem 'rails', '~> 5.2.1'
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'redis', '~> 4'
  gem 'redis-store', '~> 1.9'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  gem 'redis-rails'
end

appraise 'rails5-postgres-sidekiq' do
  gem 'rails', '~> 5.2.1'
  gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  gem 'sidekiq'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails6-mysql2' do
  gem 'rails', '~> 6.0.0'
  gem 'activerecord-jdbcmysql-adapter', '>= 60', platform: :jruby # try remove >= 60
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
end

appraise 'rails6-postgres' do
  gem 'rails', '~> 6.0.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails6-semantic-logger' do
  gem 'rails', '~> 6.0.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'rails_semantic_logger', '~> 4.0'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails6-postgres-redis' do
  gem 'rails', '~> 6.0.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
  gem 'redis', '>= 4.0.1'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails6-postgres-redis-activesupport' do
  gem 'rails', '~> 6.0.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
  gem 'redis', '~> 4'
  gem 'redis-store', '~> 1.9'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  gem 'redis-rails'
end

appraise 'rails6-postgres-sidekiq' do
  gem 'rails', '~> 6.0.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 60', platform: :jruby
  gem 'sidekiq'
  gem 'activejob'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails61-mysql2' do
  gem 'rails', '~> 6.1.0'
  gem 'activerecord-jdbcmysql-adapter', '>= 61', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  gem 'mail', '~> 2.7.1' # Somehow 2.8.x breaks ActionMailer test in jruby
end

appraise 'rails61-postgres' do
  gem 'rails', '~> 6.1.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails61-postgres-redis' do
  gem 'rails', '~> 6.1.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
  gem 'redis', '>= 4.2.5'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails61-postgres-sidekiq' do
  gem 'rails', '~> 6.1.0'
  gem 'activerecord-jdbcpostgresql-adapter', '>= 61', platform: :jruby
  gem 'sidekiq', '>= 6.1.2'
  gem 'sprockets', '< 4'
  gem 'lograge', '~> 0.11'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
end

appraise 'rails61-semantic-logger' do
  gem 'rails', '~> 6.1.0'
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

appraise 'aws' do
  gem 'aws-sdk'
  gem 'shoryuken'

  # https://www.ruby-lang.org/en/news/2024/05/16/dos-rexml-cve-2024-35176/
  # `rexml` 3.2.7+ breaks because of strscan incompatibility
  # `strsan` 3.1.0 does not fix the issue and raise TypeError when StringScanner#scan is given a string instead of Regexp
  gem 'rexml', '= 3.2.6'
end

appraise 'http' do
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
  gem 'faraday'
  gem 'http', '~> 4' # TODO: Fix test breakage and flakiness for 5+
  gem 'httpclient'
  gem 'rest-client'
  gem 'typhoeus'
end

build_coverage_matrix('stripe', 7..12, min: '5.15.0')
build_coverage_matrix('opensearch', 2..3, gem: 'opensearch-ruby')
build_coverage_matrix('elasticsearch', 7..8)

appraise 'relational_db' do
  gem 'activerecord', '~> 5'
  gem 'delayed_job'
  gem 'delayed_job_active_record'
  gem 'makara'
  gem 'activerecord-jdbcmysql-adapter', '>= 52', platform: :jruby
  gem 'activerecord-jdbcpostgresql-adapter', '>= 52', platform: :jruby
  gem 'sequel'
  gem 'activerecord-jdbcsqlite3-adapter', '>= 52', platform: :jruby
end

appraise 'activesupport' do
  gem 'activesupport', '~> 5'

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
  gem 'dalli', '>= 3.0.0'
  gem 'i18n', '1.8.7', platform: :jruby # Removal pending: https://github.com/ruby-i18n/i18n/issues/555#issuecomment-772112169
  gem 'mongo', '>= 2.8.0', '< 2.15.0' # TODO: FIX TEST BREAKAGES ON >= 2.15 https://github.com/DataDog/dd-trace-rb/issues/1596
  gem 'rack-test' # Dev dependencies for testing rack-based code
  gem 'rake', '>= 12.3'
  gem 'resque'
  gem 'roda', '>= 2.0.0'
  gem 'semantic_logger', '~> 4.0'
  gem 'sidekiq'
  gem 'sneakers', '>= 2.12.0'
  gem 'bunny', '~> 2.19.0' # uninitialized constant OpenSSL::SSL::TLS1_3_VERSION for jruby, https://github.com/ruby-amqp/bunny/issues/645
  gem 'sucker_punch'
  gem 'que', '>= 1.0.0', '< 2.0.0'
end

[
  '2.0',
].each do |v|
  appraise "graphql-#{v}" do
    gem 'rails', '~> 6.1.0'
    gem 'graphql', "~> #{v}.0"
    gem 'sprockets', '< 4'
    gem 'lograge', '~> 0.11'
  end
end

[1, 2, 3].each do |n|
  appraise "rack-#{n}" do
    gem 'rack', "~> #{n}"
    gem 'rack-contrib'
    gem 'rack-test' # Dev dependencies for testing rack-based code
  end
end

[2].each do |n|
  appraise "sinatra-#{n}" do
    gem 'sinatra', "~> #{n}"
    gem 'rack-contrib'
    gem 'rack-test' # Dev dependencies for testing rack-based code
  end
end

[3, 4, 5].each do |n|
  appraise "redis-#{n}" do
    gem 'redis', "~> #{n}"
  end
end

appraise 'contrib-old' do
  gem 'dalli', '< 3.0.0'
  gem 'faraday', '0.17'
  gem 'presto-client', '>= 0.5.14' # Renamed to trino-client in >= 1.0

  gem 'qless', '0.10.0' # Newer releases require `rusage`, which is not available for JRuby
  gem 'redis', '< 4' # Missing redis version cap for `qless`
end

appraise 'core-old' do
  gem 'dogstatsd-ruby', '~> 4'
end
