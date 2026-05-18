# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/compact_array_cop'

RSpec.describe CustomCops::CompactArrayCop do
  subject(:cop) { described_class.new }

  describe 'ternary to compact detection' do
    it 'registers an offense for x ? [x] : []' do
      expect_offense(<<~RUBY)
        hook ? [hook] : []
        ^^^^^^^^^^^^^^^^^^ CustomCops/CompactArrayCop: Use `[hook].compact` instead of `hook ? [hook] : []`.
      RUBY

      expect_correction(<<~RUBY)
        [hook].compact
      RUBY
    end

    it 'does not register an offense when condition and element differ' do
      expect_no_offenses(<<~RUBY)
        x ? [y] : []
      RUBY
    end

    it 'does not register an offense for non-empty false branch' do
      expect_no_offenses(<<~RUBY)
        hook ? [hook] : [default]
      RUBY
    end

    it 'does not register an offense for multi-element true branch' do
      expect_no_offenses(<<~RUBY)
        hook ? [hook, extra] : []
      RUBY
    end
  end
end
