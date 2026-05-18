# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/nil_safe_string_cop'

RSpec.describe CustomCops::NilSafeStringCop do
  subject(:cop) { described_class.new }

  describe "|| '' detection" do
    it "registers an offense for x || ''" do
      expect_offense(<<~RUBY)
        name || ''
        ^^^^^^^^^^ CustomCops/NilSafeStringCop: Use `.to_s` instead of `|| ''` for nil-safe string conversion.
      RUBY

      expect_correction(<<~RUBY)
        name.to_s
      RUBY
    end

    it 'registers an offense for x || ""' do
      expect_offense(<<~RUBY)
        name || ""
        ^^^^^^^^^^ CustomCops/NilSafeStringCop: Use `.to_s` instead of `|| ''` for nil-safe string conversion.
      RUBY

      expect_correction(<<~RUBY)
        name.to_s
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
  end
end
