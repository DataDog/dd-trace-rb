# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/nil_safe_string_cop'

RSpec.describe CustomCops::NilSafeStringCop do
  subject(:cop) { described_class.new }

  describe "|| '' detection" do
    it "registers an offense for variable || ''" do
      expect_offense(<<~RUBY)
        name || ''
        ^^^^^^^^^^ CustomCops/NilSafeStringCop: Use `.to_s` instead of `|| ''` for nil-safe string conversion.
      RUBY

      expect_correction(<<~RUBY)
        name.to_s
      RUBY
    end

    it 'registers an offense for variable || ""' do
      expect_offense(<<~RUBY)
        name || ""
        ^^^^^^^^^^ CustomCops/NilSafeStringCop: Use `.to_s` instead of `|| ''` for nil-safe string conversion.
      RUBY

      expect_correction(<<~RUBY)
        name.to_s
      RUBY
    end

    it "registers an offense for method call || ''" do
      expect_offense(<<~RUBY)
        user.name || ''
        ^^^^^^^^^^^^^^^ CustomCops/NilSafeStringCop: Use `.to_s` instead of `|| ''` for nil-safe string conversion.
      RUBY

      expect_correction(<<~RUBY)
        user.name.to_s
      RUBY
    end

    it "registers an offense for chained method call || ''" do
      expect_offense(<<~RUBY)
        response.body.message || ''
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ CustomCops/NilSafeStringCop: Use `.to_s` instead of `|| ''` for nil-safe string conversion.
      RUBY

      expect_correction(<<~RUBY)
        response.body.message.to_s
      RUBY
    end

    it 'does not register an offense for || with non-empty string' do
      expect_no_offenses(<<~RUBY)
        name || 'default'
      RUBY
    end

    it 'does not register an offense for || with variable' do
      expect_no_offenses(<<~RUBY)
        name || default_name
      RUBY
    end

    it 'does not register an offense for || with nil' do
      expect_no_offenses(<<~RUBY)
        name || nil
      RUBY
    end

    it 'does not register an offense for .to_s' do
      expect_no_offenses(<<~RUBY)
        name.to_s
      RUBY
    end
  end
end
