# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/rspec/support"
require "rubocop/custom_cops/time_now_usage_cop"

RSpec.describe CustomCops::TimeNowUsageCop do
  subject(:cop) { described_class.new }

  describe "Time.now usage detection" do
    it "registers an offense for Time.now inside the Datadog namespace" do
      expect_offense(<<~RUBY)
        module Datadog
          Time.now
          ^^^^^^^^ CustomCops/TimeNowUsageCop: Avoid direct usage of `Time.now`. Use `Core::Utils::Time.now` instead, which captures the original (non-monkey-patched) implementation once at load time and is safe to call from any thread.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          Core::Utils::Time.now
        end
      RUBY
    end

    it "registers an offense for deeply nested Time.now" do
      expect_offense(<<~RUBY)
        module Datadog
          module Core
            module SomeComponent
              def self.now
                Time.now
                ^^^^^^^^ CustomCops/TimeNowUsageCop: Avoid direct usage of `Time.now`. Use `Core::Utils::Time.now` instead, which captures the original (non-monkey-patched) implementation once at load time and is safe to call from any thread.
              end
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          module Core
            module SomeComponent
              def self.now
                Core::Utils::Time.now
              end
            end
          end
        end
      RUBY
    end

    it "registers an offense for Time.now outside of the Datadog namespace" do
      expect_offense(<<~RUBY)
        Time.now
        ^^^^^^^^ CustomCops/TimeNowUsageCop: Avoid direct usage of `Time.now`. Use `Datadog::Core::Utils::Time.now` instead, which captures the original (non-monkey-patched) implementation once at load time and is safe to call from any thread.
      RUBY

      expect_correction(<<~RUBY)
        Datadog::Core::Utils::Time.now
      RUBY
    end

    it "registers an offense for Time.now when top module is not Datadog" do
      expect_offense(<<~RUBY)
        module MyApp
          module Datadog
            Time.now
            ^^^^^^^^ CustomCops/TimeNowUsageCop: Avoid direct usage of `Time.now`. Use `::Datadog::Core::Utils::Time.now` instead, which captures the original (non-monkey-patched) implementation once at load time and is safe to call from any thread.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        module MyApp
          module Datadog
            ::Datadog::Core::Utils::Time.now
          end
        end
      RUBY
    end

    it "registers an offense for ::Time.now" do
      expect_offense(<<~RUBY)
        module Datadog
          ::Time.now
          ^^^^^^^^^^ CustomCops/TimeNowUsageCop: Avoid direct usage of `Time.now`. Use `Core::Utils::Time.now` instead, which captures the original (non-monkey-patched) implementation once at load time and is safe to call from any thread.
        end
      RUBY

      expect_correction(<<~RUBY)
        module Datadog
          Core::Utils::Time.now
        end
      RUBY
    end

    it "does not register an offense for Core::Utils::Time.now" do
      expect_no_offenses(<<~RUBY)
        module Datadog
          Core::Utils::Time.now
        end
      RUBY
    end

    it "does not register an offense for Datadog::Core::Utils::Time.now" do
      expect_no_offenses(<<~RUBY)
        Datadog::Core::Utils::Time.now
      RUBY
    end

    it "does not register an offense for other Time methods" do
      expect_no_offenses(<<~RUBY)
        module Datadog
          Time.at(0)
          Time.parse("2020-01-01")
        end
      RUBY
    end

    it "does not register an offense for #now on an unrelated receiver" do
      expect_no_offenses(<<~RUBY)
        module Datadog
          SomeOtherClock.now
        end
      RUBY
    end
  end
end
