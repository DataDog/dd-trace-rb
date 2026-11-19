# frozen_string_literal: true

require "spec_helper"

RSpec.describe Datadog::SymbolDatabase do
  describe ".supported_runtime?" do
    context "on MRI 2.7+" do
      before do
        stub_const("RUBY_ENGINE", "ruby")
        stub_const("RUBY_VERSION", "2.7.0")
        stub_const("Datadog::RubyVersion::CURRENT_RUBY_VERSION", Gem::Version.new("2.7.0"))
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

    context "on MRI older than 2.7" do
      before do
        stub_const("RUBY_ENGINE", "ruby")
        stub_const("RUBY_VERSION", "2.6.0")
        stub_const("Datadog::RubyVersion::CURRENT_RUBY_VERSION", Gem::Version.new("2.6.0"))
      end

      it "returns false" do
        expect(described_class.supported_runtime?).to be false
      end
    end
  end
end
