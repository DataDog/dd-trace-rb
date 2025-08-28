# frozen_string_literal: true

# Cannot use `skip:` as it will still raise a NameError (uninitialized constant CustomCops::RuboCop)
return if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7')

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
          ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
                ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
        ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
      RUBY

      expect_correction(<<~RUBY)
        Datadog::DATADOG_ENV['DATADOG_API_KEY']
      RUBY
    end

    it 'registers an offense for ENV access outside of Datadog namespace with a comment' do
      expect_offense(<<~RUBY)
        # frozen_string_literal: true
        ENV['DATADOG_API_KEY']
        ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
        ^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
            ^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use Datadog::DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
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
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          DATADOG_ENV.member?('DATADOG_API_KEY')
        end
      RUBY
    end

    it 'registers an offense for ENV.values_at' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV.values_at('KEY1', 'KEY2')
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV to access environment variables. See docs/AccessEnvironmentVariables.md for details.
        end
      RUBY

      expect_no_corrections
    end

    it 'registers an offense for ENV' do
      expect_offense(<<~RUBY)
        module Datadog
          ENV
          ^^^ CustomCops/EnvUsageCop: Avoid direct usage of ENV. Use DATADOG_ENV with a method call to access environment variables. See docs/AccessEnvironmentVariables.md for details.
        end
      RUBY

      expect_no_corrections
    end
  end
end
