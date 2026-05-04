# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/exception_message_cop'

RSpec.describe CustomCops::ExceptionMessageCop do
  subject(:cop) { described_class.new }

  describe 'bare exception interpolation' do
    it 'registers an offense for bare #{e} in interpolation and auto-corrects to .message' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e}")
                             ^ CustomCops/ExceptionMessageCop: Use `e.message` instead of bare `#{e}` interpolation. `#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e.message}")
        end
      RUBY
    end

    it 'registers an offense for bare #{e} in a longer interpolated string and auto-corrects' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class} happened: #{e}")
                                      ^ CustomCops/ExceptionMessageCop: Use `e.message` instead of bare `#{e}` interpolation. `#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class} happened: #{e.message}")
        end
      RUBY
    end

    it 'does not register an offense outside a rescue block' do
      expect_no_offenses(<<~'RUBY')
        e = SomeObject.new
        log("#{e}")
      RUBY
    end

    it 'does not register an offense for `e.message` (the preferred form)' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e.message}")
        end
      RUBY
    end

    it 'does not flag bare `e` outside string interpolation' do
      # `raise e`, `log(e)`, etc. are valid uses of the rescue variable.
      expect_no_offenses(<<~RUBY)
        begin
          something
        rescue => e
          raise e
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
          log("#{e.class.name}: #{e.message}")
                 ^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e.message}")
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
    it 'registers offenses for both e.class.name and bare e and auto-corrects both' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class.name} #{e}")
                                 ^ CustomCops/ExceptionMessageCop: Use `e.message` instead of bare `#{e}` interpolation. `#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.
                 ^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class} #{e.message}")
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

  describe 'variable shadowing' do
    it 'does not register an offense when a block parameter shadows the rescue variable' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          errors.each { |e| log("#{e}") }
        end
      RUBY
    end

    it 'does not register an offense when a destructured block parameter shadows the rescue variable' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          pairs.each { |(k, e)| log("#{e}") }
        end
      RUBY
    end

    it 'does not register an offense for the missing-class check when shadowed' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          errors.each { |e| log("error: #{e.message}") }
        end
      RUBY
    end

    it 'does not register an offense when a method definition uses the same parameter name' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          define_method(:helper) do |e|
            log("#{e}")
          end
        end
      RUBY
    end

    it 'still registers an offense for the rescue variable used outside the shadowing block' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          errors.each { |e| log(e) }
          log("#{e.class}: #{e}")
                             ^ CustomCops/ExceptionMessageCop: Use `e.message` instead of bare `#{e}` interpolation. `#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.
        end
      RUBY
    end
  end

  describe 'different rescue variable names' do
    it 'registers an offense when the rescue variable is named differently' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.class}: #{err}")
                               ^^^ CustomCops/ExceptionMessageCop: Use `e.message` instead of bare `#{e}` interpolation. `#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.class}: #{err.message}")
        end
      RUBY
    end

    it 'registers an offense for err.class.name' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.class.name}: #{err.message}")
                 ^^^^^^^^^^^^^^ CustomCops/ExceptionMessageCop: Use `.class` instead of `.class.name`. `Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => err
          log("#{err.class}: #{err.message}")
        end
      RUBY
    end
  end

  describe 'missing class detection' do
    it 'flags bare `#{e}` first; the missing-class offense surfaces on a second pass after autocorrect' do
      # RuboCop deduplicates offenses on the same node, so the first pass shows
      # only the bare-exception offense. After autocorrect to `e.message`, a
      # subsequent pass flags the still-missing class — verified in the next test.
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("error: #{e}")
                        ^ CustomCops/ExceptionMessageCop: Use `e.message` instead of bare `#{e}` interpolation. `#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.
        end
      RUBY

      expect_correction(<<~'RUBY')
        begin
          something
        rescue => e
          log("error: #{e.message}")
        end
      RUBY
    end

    it 'registers a missing-class offense for `#{e.message}` without class' do
      expect_offense(<<~'RUBY')
        begin
          something
        rescue => e
          log("error: #{e.message}")
                        ^^^^^^^^^ CustomCops/ExceptionMessageCop: Include `#{e.class}` when interpolating an exception. The convention is `"#{e.class}: #{e.message}"`.
        end
      RUBY
    end

    it 'does not register a missing-class offense when class is present in the same string' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class}: #{e.message}")
        end
      RUBY
    end

    it 'does not register a missing-class offense when class is present elsewhere in the same string' do
      expect_no_offenses(<<~'RUBY')
        begin
          something
        rescue => e
          log("#{e.class} happened: #{e.message}")
        end
      RUBY
    end

    it 'does not register a missing-class offense outside a rescue block' do
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
          log("#{e.class}: #{e.message}")
        end
      RUBY
    end
  end
end
