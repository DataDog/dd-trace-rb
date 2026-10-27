# frozen_string_literal: true

require "spec_helper"
require "datadog/core/remote/configuration/json_coercion"

RSpec.describe Datadog::Core::Remote::Configuration::JSONCoercion do
  describe ".coerce_integer" do
    subject(:coerced) { described_class.coerce_integer(value) }

    context "with an Integer" do
      let(:value) { 645 }

      it "returns the Integer" do
        expect(coerced).to eq(645)
      end
    end

    context "with a base-10 integer String" do
      let(:value) { "645" }

      it "coerces to the Integer" do
        expect(coerced).to eq(645)
      end
    end

    context "with a negative integer String" do
      let(:value) { "-5" }

      it "coerces to the Integer" do
        expect(coerced).to eq(-5)
      end
    end

    context "with a non-numeric String" do
      let(:value) { "abc" }

      it "returns nil" do
        expect(coerced).to be_nil
      end
    end

    context "with a decimal String" do
      let(:value) { "4.5" }

      it "returns nil" do
        expect(coerced).to be_nil
      end
    end

    context "with a Float" do
      let(:value) { 45.0 }

      it "returns nil" do
        expect(coerced).to be_nil
      end
    end

    context "with nil" do
      let(:value) { nil }

      it "returns nil" do
        expect(coerced).to be_nil
      end
    end

    context "with a Hash" do
      let(:value) { {} }

      it "returns nil" do
        expect(coerced).to be_nil
      end
    end

    context "with a boolean" do
      let(:value) { true }

      it "returns nil" do
        expect(coerced).to be_nil
      end
    end
  end
end
