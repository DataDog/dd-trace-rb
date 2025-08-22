# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../rubocop/custom_cops/env_usage_cop'

RSpec.describe CustomCops::EnvUsageCop do
  subject(:cop) { described_class.new }

  describe 'ENV usage detection' do
    it 'registers an offense for ENV hash access' do
      expect_offense(<<~RUBY)
        ENV['DATADOG_API_KEY']
        ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        Datadog.get_environment_variable('DATADOG_API_KEY')
      RUBY
    end

    it 'registers an offense for ENV.fetch' do
      expect_offense(<<~RUBY)
        ENV.fetch('DATADOG_API_KEY')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        Datadog.get_environment_variable('DATADOG_API_KEY')
      RUBY
    end

    it 'registers an offense for ENV.fetch with default' do
      expect_offense(<<~RUBY)
        ENV.fetch('DATADOG_API_KEY', 'default')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        Datadog.get_environment_variable('DATADOG_API_KEY') || 'default'
      RUBY
    end

    it 'registers an offense for ENV.key?' do
      expect_offense(<<~RUBY)
        ENV.key?('DATADOG_API_KEY')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        !Datadog.get_environment_variable('DATADOG_API_KEY').nil?
      RUBY
    end

    it 'registers an offense for ENV.has_key?' do
      expect_offense(<<~RUBY)
        ENV.has_key?('DATADOG_API_KEY')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        !Datadog.get_environment_variable('DATADOG_API_KEY').nil?
      RUBY
    end

    it 'registers an offense for ENV.include?' do
      expect_offense(<<~RUBY)
        ENV.include?('DATADOG_API_KEY')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        !Datadog.get_environment_variable('DATADOG_API_KEY').nil?
      RUBY
    end

    it 'registers an offense for ENV.member?' do
      expect_offense(<<~RUBY)
        ENV.member?('DATADOG_API_KEY')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        !Datadog.get_environment_variable('DATADOG_API_KEY').nil?
      RUBY
    end

    it 'registers an offense for !ENV.key?' do
      expect_offense(<<~RUBY)
        !ENV.key?('DATADOG_API_KEY')
         ^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        Datadog.get_environment_variable('DATADOG_API_KEY').nil?
      RUBY
    end

    it 'registers an offense for ENV with symbol key' do
      expect_offense(<<~RUBY)
        ENV[:DATADOG_API_KEY.to_s]
        ^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        Datadog.get_environment_variable(:DATADOG_API_KEY.to_s)
      RUBY
    end

    it 'registers an offense for ENV with variable key' do
      expect_offense(<<~RUBY)
        key = 'DATADOG_API_KEY'
        ENV[key]
        ^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        key = 'DATADOG_API_KEY'
        Datadog.get_environment_variable(key)
      RUBY
    end

    it 'registers an offense for ENV in method call' do
      expect_offense(<<~RUBY)
        def get_api_key
          ENV['DATADOG_API_KEY']
          ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        def get_api_key
          Datadog.get_environment_variable('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV in conditional' do
      expect_offense(<<~RUBY)
        if ENV['DEBUG']
           ^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
          puts 'Debug mode'
        end
      RUBY

      expect_correction(<<~RUBY)
        if Datadog.get_environment_variable('DEBUG')
          puts 'Debug mode'
        end
      RUBY
    end

    it 'registers an offense for ENV in assignment' do
      expect_offense(<<~RUBY)
        api_key = ENV['DATADOG_API_KEY']
                  ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        api_key = Datadog.get_environment_variable('DATADOG_API_KEY')
      RUBY
    end

    it 'registers an offense for ENV in interpolation' do
      # 1 char offset to avoid actual interpolation
      expect_offense(<<~RUBY)
        "API Key: \#{ENV['DATADOG_API_KEY']}"
                    ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        "API Key: \#{Datadog.get_environment_variable('DATADOG_API_KEY')}"
      RUBY
    end

    it 'registers an offense for ENV in array' do
      expect_offense(<<~RUBY)
        [ENV['KEY1'], ENV['KEY2']]
         ^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
                      ^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        [Datadog.get_environment_variable('KEY1'), Datadog.get_environment_variable('KEY2')]
      RUBY
    end

    it 'registers an offense for ENV in hash' do
      expect_offense(<<~RUBY)
        { api_key: ENV['DATADOG_API_KEY'] }
                   ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        { api_key: Datadog.get_environment_variable('DATADOG_API_KEY') }
      RUBY
    end

    it 'registers an offense for ENV.values_at' do
      expect_offense(<<~RUBY)
        ENV.values_at('KEY1', 'KEY2')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY
    end

    it 'registers an offense for ENV' do
      expect_offense(<<~RUBY)
        ENV
        ^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.
      RUBY
    end
  end

  describe 'non-ENV usage' do
    it 'does not register an offense for other constants' do
      expect_no_offenses(<<~RUBY)
        OTHER_CONST['key']
      RUBY
    end

    it 'does not register an offense for other variables' do
      expect_no_offenses(<<~RUBY)
        env_var['key']
      RUBY
    end
  end
end
