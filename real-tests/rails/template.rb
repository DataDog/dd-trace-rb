ENV["RAILS_ENV"] = 'production'
ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = "1"
db_name =  "rails-app"

gem "dogstatsd-ruby", ">= 3.3.0"
gem 'ddtrace', path: "../../.."

gem 'redis-rack-cache', '2.2.1' # For caching
gem 'dotenv-rails', '2.7.6' # For database and redis connection
gem 'ruby-prof', '~> 1.4'

# gem 'pry-nav' # TODO: remove

run_bundle

# 'config/environments/*.rb'
# config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }

FileUtils.cp "../../../.env", ".env"

#<%= ENV.fetch('TEST_POSTGRES_DB', 'postgres') %>
create_file "config/database.yml", <<-YAML, force: true
production:
  adapter: 'postgresql'
  encoding: 'unicode'
  database: #{db_name}
  username: <%= ENV.fetch('TEST_POSTGRES_USER', 'postgres') %>
  password: <%= ENV.fetch('TEST_POSTGRES_PASSWORD', 'postgres') %>
  host: <%= ENV.fetch('TEST_POSTGRES_HOST', '127.0.0.1') %>
  port: <%= ENV.fetch('TEST_POSTGRES_PORT', 5432) %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
YAML

#
# insert_into_file 'config/application.rb', before: a, do
#   <<-RUBY
#   require 'dotenv'
#   Dotenv.load('../../../.env')
#   RUBY
# end


insert_into_file "config/environments/production.rb", before: /^end/ do
  <<-'RUBY'
  config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
  config.action_dispatch.rack_cache = {
    verbose: false,
    metastore: "redis://#{ENV['TEST_REDIS_HOST']}:#{ENV['TEST_REDIS_PORT']}/1/rack_cache_metastore",
    entitystore: "redis://#{ENV['TEST_REDIS_HOST']}:#{ENV['TEST_REDIS_PORT']}/1/rack_cache_entitystore"
  }
  RUBY
end

generate :scaffold, "person name:string"

route "root to: 'people#index'"

rails_command("db:drop")
rails_command("db:create")
rails_command("db:migrate")

create_file "db/seeds.rb", <<-'RUBY', force: true
  100.times do |i|
    Person.create(name: "Person_#{i}")
  end
RUBY

rails_command("db:seed")

initializer 'datadog.rb', <<-RUBY
  Datadog.configure do |c|
    c.use :rails
    c.use :redis

    c.runtime_metrics.enabled = true
    c.diagnostics.health_metrics.enabled = true
  end
RUBY

# Run before Puma is initialized
append_to_file 'config/application.rb', <<-'RUBY'
require 'puma/events'

require 'ruby-prof'
RubyProf.measure_mode = RubyProf::PROCESS_TIME

require 'fileutils'

Puma::Events.prepend(Module.new do
  def initialize(*args)
    super

    register(:state) do |state|
      case state
      when :running
        RubyProf.start
      when :done
        result = RubyProf.stop

        dir = File.join('..', 'tmp', 'benchmark')
        FileUtils.mkdir_p(dir)

        printer = RubyProf::CallTreePrinter.new(result)
        printer.print(path: dir)
      end
    end
  end
end)

RUBY

# after_bundle do
#   git :init
#   git add: "."
#   git commit: %Q{ -m 'Initial commit' }
# end


# export SECRET_KEY_BASE="7d4d2daa8c4b79efe9a9206d20b877a2cde9c90f46987c6ec24f811d06eddb9d554742fc6c25cd7ec73ce9e698424b152e78bb8bf61da8b669c53677f04ab0b8"
# export RAILS_MAX_THREADS=100 # Limited by Postgres connection limit
# export RAILS_ENV=production
# export POSTGRES_HOST=localhost
# export REDIS_URL=redis://localhost:6379/0


# bundle exec rake db:migrate || bundle exec rake db:setup
# bin/rails s

FileUtils.cp('../template.rb', '.')
