require 'spec_helper'

RSpec.describe Datadog::Tracing::Contrib do
  root = Gem::Specification.find_by_name('ddtrace').gem_dir

  # Our module names are camelized directory name with some exceptions
  mapping = {
    'action_cable' => 'ActionCable',
    'action_mailer' => 'ActionMailer',
    'action_pack' => 'ActionPack',
    'action_view' => 'ActionView',
    'active_job' => 'ActiveJob',
    'active_model_serializers' => 'ActiveModelSerializers',
    'active_record' => 'ActiveRecord',
    'active_support' => 'ActiveSupport',
    'aws' => 'Aws',
    'concurrent_ruby' => 'ConcurrentRuby',
    'dalli' => 'Dalli',
    'delayed_job' => 'DelayedJob',
    'elasticsearch' => 'Elasticsearch',
    'ethon' => 'Ethon',
    'excon' => 'Excon',
    'faraday' => 'Faraday',
    'grape' => 'Grape',
    'graphql' => 'GraphQL', # exception
    'grpc' => 'GRPC', # exception
    'hanami' => 'Hanami',
    'http' => 'HTTP', # exception
    'httpclient' => 'Httpclient',
    'httprb' => 'Httprb',
    'kafka' => 'Kafka',
    'lograge' => 'Lograge',
    'mongodb' => 'MongoDB', # exception
    'mysql2' => 'Mysql2',
    'opensearch' => 'OpenSearch', # exception
    'pg' => 'Pg',
    'presto' => 'Presto',
    'qless' => 'Qless',
    'que' => 'Que',
    'racecar' => 'Racecar',
    'rack' => 'Rack',
    'rails' => 'Rails',
    'rake' => 'Rake',
    'redis' => 'Redis',
    'resque' => 'Resque',
    'rest_client' => 'RestClient',
    'roda' => 'Roda',
    'semantic_logger' => 'SemanticLogger',
    'sequel' => 'Sequel',
    'shoryuken' => 'Shoryuken',
    'sidekiq' => 'Sidekiq',
    'sinatra' => 'Sinatra',
    'sneakers' => 'Sneakers',
    'stripe' => 'Stripe',
    'sucker_punch' => 'SuckerPunch',
    'trilogy' => 'Trilogy'
  }

  Dir.chdir("#{root}/lib/datadog/tracing/contrib") do |pwd|
    Dir.glob('*/integration.rb').each do |path|
      it "ensures #{pwd}/#{path} is loaded" do
        directory = File.dirname path
        ruby_module = mapping.fetch(directory) # raise key error if not found

        expect { Object.const_get "::Datadog::Tracing::Contrib::#{ruby_module}" }.not_to raise_error
      end
    end
  end
end
