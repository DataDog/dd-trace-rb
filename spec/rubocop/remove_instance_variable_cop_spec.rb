# frozen_string_literal: true

require "spec_helper"

require "rubocop"
require "rubocop/rspec/support"
require "rubocop/custom_cops/remove_instance_variable_cop"

RSpec.describe CustomCops::RemoveInstanceVariableCop do
  subject(:cop) { described_class.new }

  let(:message) do
    "CustomCops/RemoveInstanceVariableCop: Avoid `remove_instance_variable`: it is slow and changes the " \
      "object's shape, which makes later instance variable accesses polymorphic. Assign `nil` instead " \
      "(and keep a separate flag if `nil` is a meaningful value)."
  end

  describe "direct calls" do
    it "registers an offense for an implicit receiver" do
      expect_offense(<<~RUBY)
        def reset
          remove_instance_variable(:@foo)
          ^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
        end
      RUBY
    end

    it "registers an offense for an explicit receiver" do
      expect_offense(<<~RUBY)
        other.remove_instance_variable(:@foo)
              ^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
      RUBY
    end

    it "registers an offense for a safe-navigation call" do
      expect_offense(<<~RUBY)
        other&.remove_instance_variable(:@foo)
               ^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
      RUBY
    end

    it "registers an offense for a call without parentheses" do
      expect_offense(<<~RUBY)
        self.remove_instance_variable :@foo
             ^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
      RUBY
    end

    it "registers an offense for a multi-line call" do
      expect_offense(<<~RUBY)
        value = remove_instance_variable(
                ^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
          :@foo,
        )
      RUBY
    end
  end

  describe "reflective calls" do
    %w[send __send__ public_send].each do |method|
      it "registers an offense for #{method} with a symbol" do
        expect_offense(<<~RUBY)
          other.#{method}(:remove_instance_variable, :@foo)
          #{" " * (7 + method.length)}^^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
        RUBY
      end
    end

    it "registers an offense for send with a string" do
      expect_offense(<<~RUBY)
        other.send("remove_instance_variable", :@foo)
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^ #{message}
      RUBY
    end
  end

  describe "code that resembles the pattern" do
    it "does not register an offense for assigning nil" do
      expect_no_offenses(<<~RUBY)
        @foo = nil
      RUBY
    end

    it "does not register an offense for other instance variable methods" do
      expect_no_offenses(<<~RUBY)
        other.instance_variable_get(:@foo)
        other.instance_variable_set(:@foo, nil)
        other.instance_variable_defined?(:@foo)
        other.remove_instance_variables(:@foo)
      RUBY
    end

    it "does not register an offense for send with another method" do
      expect_no_offenses(<<~RUBY)
        other.send(:instance_variable_get, :@foo)
        other.send(:remove_class_variable, :@@foo)
        other.public_send(*args)
        other.send
      RUBY
    end

    it "does not register an offense for a dynamic method name" do
      expect_no_offenses(<<~RUBY)
        other.send(name, :@foo)
      RUBY
    end

    it "does not register an offense for mentions in strings, symbols and comments" do
      expect_no_offenses(<<~RUBY)
        # remove_instance_variable(:@foo)
        message = "remove_instance_variable"
        name = :remove_instance_variable
      RUBY
    end

    it "does not register an offense for defining a method of the same name" do
      expect_no_offenses(<<~RUBY)
        def remove_instance_variable(name)
          super
        end
      RUBY
    end
  end
end
