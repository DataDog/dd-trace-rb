# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/exception_message_cop'

RSpec.describe CustomCops::ExceptionMessageCop do
  subject(:cop) { described_class.new }

  describe 'e.message detection' do
    it 'registers an offense for e.message in string interpolation and auto-corrects' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.message}")
                 ^^^^^^^^^ CustomCops/ExceptionMessageCop: Use the exception directly instead of `.message`. `to_s` and `message` have different contracts; `#{e}` calls `to_s`, which is the convention.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e}")
        end
      RUBY
    end

    it 'registers an offense for e.message in a longer interpolated string and auto-corrects' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("error: #{e.class}: #{e.message}")
                                    ^^^^^^^^^ CustomCops/ExceptionMessageCop: Use the exception directly instead of `.message`. `to_s` and `message` have different contracts; `#{e}` calls `to_s`, which is the convention.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("error: #{e.class}: #{e}")
        end
      RUBY
    end

    it 'registers an offense for e.message outside interpolation but does not auto-correct' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log(e.message)
              ^^^^^^^^^ CustomCops/ExceptionMessageCop: Use the exception directly instead of `.message`. `to_s` and `message` have different contracts; `#{e}` calls `to_s`, which is the convention.
        end
      RUBY

      expect_no_corrections
    end

    it 'does not register an offense outside a rescue block' do
      expect_no_offenses(<<~RUBY)
        e = SomeObject.new
        log(e.message)
      RUBY
    end

    it 'does not register an offense for message with arguments' do
      expect_no_offenses(<<~RUBY)
        begin
          something
        rescue => e
          log(e.message(:detailed))
        end
      RUBY
    end
  end

  describe 'e.class.name detection' do
    it 'registers an offense for e.class.name in string interpolation and auto-corrects' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class.name}: #{e}")
                 ^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e}")
        end
      RUBY
    end

    it 'registers an offense for e.class.name outside interpolation but does not auto-correct' do
      expect_offense(<<~RUBY)
        begin
          something
        rescue => e
          log(e.class.name)
              ^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_no_corrections
    end

    it 'does not register an offense outside a rescue block' do
      expect_no_offenses(<<~RUBY)
        e = SomeObject.new
        log(e.class.name)
      RUBY
    end
  end

  describe 'combined patterns' do
    it 'registers offenses for both e.class.name and e.message in one string' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class.name} #{e.message}")
                                 ^^^^^^^^^ CustomCops/ExceptionMessageCop: Use the exception directly instead of `.message`. `to_s` and `message` have different contracts; `#{e}` calls `to_s`, which is the convention.
                 ^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class} #{e}")
        end
      RUBY
    end
  end

  describe 'inline rescue' do
    it 'does not register an offense for inline rescue (no rescue variable)' do
      expect_no_offenses(<<~RUBY)
        result = something rescue nil
      RUBY
    end
  end

  describe 'different rescue variable names' do
    it 'registers an offense when the rescue variable is named differently' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.message}")
                 ^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use the exception directly instead of `.message`. `to_s` and `message` have different contracts; `#{e}` calls `to_s`, which is the convention.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err}")
        end
      RUBY
    end

    it 'registers an offense for err.class.name' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.class.name}")
                 ^^^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.class}")
        end
      RUBY
    end
  end

  describe 'missing class detection' do
    it 'registers an offense for bare exception without class in interpolation' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("error: #{e}")
                        ^ CustomCops/ExceptionMessageCop: Include `#{e.class}` when interpolating an exception. The convention is `"#{e.class}: #{e}"`.
        end
      RUBY
    end

    it 'registers an offense for bare exception with different variable name' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => err
          log("error: #{err}")
                        ^^^ CustomCops/ExceptionMessageCop: Include `#{e.class}` when interpolating an exception. The convention is `"#{e.class}: #{e}"`.
        end
      RUBY
    end

    it 'does not register an offense when class is present in the same string' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e}")
        end
      RUBY
    end

    it 'does not register an offense when class is present elsewhere in the same string' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class} happened: #{e}")
        end
      RUBY
    end

    it 'does not register an offense outside a rescue block' do
      expect_no_offenses(<<~'RUBY')
        e = SomeObject.new
        log("error: #{e}")
      RUBY
    end
  end

  describe 'good patterns (no offense)' do
    it 'does not flag the correct convention' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e}")
        end
      RUBY
    end
  end
end
