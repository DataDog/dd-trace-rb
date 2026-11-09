# frozen_string_literal: true

require "spec_helper"

RSpec.describe Datadog::SymbolDatabase do
  describe ".supported_runtime?" do
    context "on MRI" do
      before do
        stub_const("RUBY_ENGINE", "ruby")
      end

      it "returns true" do
        expect(described_class.supported_runtime?).to be true
      end
    end

    context "on JRuby" do
      before { stub_const("RUBY_ENGINE", "jruby") }

      it "returns false" do
        expect(described_class.supported_runtime?).to be false
      end
    end
  end
end
