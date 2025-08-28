# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../rubocop/custom_cops/env_usage_cop'

RSpec.describe CustomCops::EnvUsageCop do
  subject(:cop) { described_class.new }

  describe 'ENV usage detection' do
    it 'registers an offense for ENV hash access' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV['DATADOG_API_KEY']
          ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV['DATADOG_API_KEY']
        end
      RUBY
    end

    it 'registers an offense for deeply nested ENV hash access' do
      expect_offense(<<~RUBY)
        module Datadog
          module Core
            module Configuration
              module Settings
                ENV['DATADOG_API_KEY']
                ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
              end
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          module Core
            module Configuration
              module Settings
                DATADOG_ENV['DATADOG_API_KEY']
              end
            end
          end
        end
      RUBY
    end

    it 'registers an offense for ENV access outside of Datadog namespace' do
      expect_offense(<<~RUBY)
        ENV['DATADOG_API_KEY']
        ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        Datadog::DATADOG_ENV['DATADOG_API_KEY']
      RUBY
    end

    it 'registers an offense for ENV access outside of Datadog namespace with a comment' do
      expect_offense(<<~RUBY)
        # frozen_string_literal: true
        ENV['DATADOG_API_KEY']
        ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        # frozen_string_literal: true
        Datadog::DATADOG_ENV['DATADOG_API_KEY']
      RUBY
    end

    it 'registers an offense for ENV access outside of Datadog namespace within a file that contains Datadog namespace' do
      expect_offense(<<~RUBY)
        module Datadog
          KEY = 'DATADOG_API_KEY'
        end
        ENV[Datadog::KEY]
        ^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables.
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          KEY = 'DATADOG_API_KEY'
        end
        Datadog::DATADOG_ENV[Datadog::KEY]
      RUBY
    end

    it 'registers an offense for ENV access when top module is not Datadog' do
      expect_offense(<<~RUBY)
        module MyApp
          module Datadog
            ENV['DATADOG_API_KEY']
            ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module MyApp
          module Datadog
            Datadog::DATADOG_ENV['DATADOG_API_KEY']
          end
        end
      RUBY
    end

    it 'registers an offense for ENV.[]' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.[]('DATADOG_API_KEY')
          ^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.[]('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV.fetch' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.fetch('DATADOG_API_KEY')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.fetch('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV.fetch with default' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.fetch('DATADOG_API_KEY', 'default')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.fetch('DATADOG_API_KEY', 'default')
        end
      RUBY
    end

    it 'registers an offense for ENV.fetch with block' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.fetch('DATADOG_API_KEY') do
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
            'default'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.fetch('DATADOG_API_KEY') do
            'default'
          end
        end
      RUBY
    end

    it 'registers an offense for ENV.fetch with inline block' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.fetch('DATADOG_API_KEY') { 'default' }
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.fetch('DATADOG_API_KEY') { 'default' }
        end
      RUBY
    end

    it 'registers an offense for ENV.key?' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.key?('DATADOG_API_KEY')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.key?('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV.has_key?' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.has_key?('DATADOG_API_KEY')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.has_key?('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV.include?' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.include?('DATADOG_API_KEY')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.include?('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV.member?' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.member?('DATADOG_API_KEY')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.member?('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for !ENV.key?' do
      expect_offense(<<~RUBY)
        module Datadog
          !ENV.key?('DATADOG_API_KEY')
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          !DATADOG_ENV.key?('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV with symbol key' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV[:DATADOG_API_KEY.to_s]
          ^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV[:DATADOG_API_KEY.to_s]
        end
      RUBY
    end

    it 'registers an offense for ENV with variable key' do
      expect_offense(<<~RUBY)
        module Datadog
          key = 'DATADOG_API_KEY'
          ENV[key]
          ^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          key = 'DATADOG_API_KEY'
          DATADOG_ENV[key]
        end
      RUBY
    end

    it 'registers an offense for ENV in method call' do
      expect_offense(<<~RUBY)
        module Datadog
          def get_api_key
            ENV['DATADOG_API_KEY']
            ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          def get_api_key
            DATADOG_ENV['DATADOG_API_KEY']
          end
        end
      RUBY
    end

    it 'registers an offense for ENV in conditional' do
      expect_offense(<<~RUBY)
        module Datadog
          if ENV['DEBUG']
             ^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
            puts 'Debug mode'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          if DATADOG_ENV['DEBUG']
            puts 'Debug mode'
          end
        end
      RUBY
    end

    it 'registers an offense for ENV in assignment' do
      expect_offense(<<~RUBY)
        module Datadog
          api_key = ENV['DATADOG_API_KEY']
                    ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          api_key = DATADOG_ENV['DATADOG_API_KEY']
        end
      RUBY
    end

    it 'registers an offense for ENV in interpolation' do
      # 1 char offset to avoid actual interpolation
      expect_offense(<<~RUBY)
        module Datadog
          "API Key: \#{ENV['DATADOG_API_KEY']}"
                      ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          "API Key: \#{DATADOG_ENV['DATADOG_API_KEY']}"
        end
      RUBY
    end

    it 'registers an offense for ENV in array' do
      expect_offense(<<~RUBY)
        module Datadog
          [ENV['KEY1'], ENV['KEY2']]
           ^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
                        ^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          [DATADOG_ENV['KEY1'], DATADOG_ENV['KEY2']]
        end
      RUBY
    end

    it 'registers an offense for ENV in hash' do
      expect_offense(<<~RUBY)
        module Datadog
          { api_key: ENV['DATADOG_API_KEY'] }
                     ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          { api_key: DATADOG_ENV['DATADOG_API_KEY'] }
        end
      RUBY
    end

    it 'registers an offense for ENV.values_at' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.values_at('KEY1', 'KEY2')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables.
        end
      RUBY
    end

    it 'registers an offense for ENV' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV
          ^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV with a method call to access environment variables.
        end
      RUBY
    end
  end

  describe 'non-ENV usage' do
    it 'does not register an offense for other constants' do
      expect_no_offenses(<<~RUBY)
        module Datadog
          OTHER_CONST['key']
        end
      RUBY
    end

    it 'does not register an offense for other variables' do
      expect_no_offenses(<<~RUBY)
        module Datadog
          env_var['key']
        end
      RUBY
    end
  end
end
