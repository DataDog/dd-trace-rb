# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/agentless/parser"

RSpec.describe Datadog::OpenFeature::Agentless::Parser do
  subject(:configuration) { described_class.parse(JSON.generate(payload)) }

  let(:attributes) do
    {
      "format" => "SERVER",
      "createdAt" => "2026-09-08T00:00:00Z",
      "environment" => {"name" => "test"},
      "flags" => {},
    }
  end
  let(:payload) do
    {
      "data" => {
        "type" => "universal-flag-configuration",
        "attributes" => attributes,
      },
    }
  end

  it "returns serialized UFC attributes" do
    expect(JSON.parse(configuration)).to eq(attributes)
  end

  shared_examples "an invalid payload" do
    it { is_expected.to be_nil }
  end

  context "with malformed JSON" do
    subject(:configuration) { described_class.parse("{") }

    it_behaves_like "an invalid payload"
  end

  context "without data" do
    let(:payload) { {} }

    it_behaves_like "an invalid payload"
  end

  context "with the wrong resource type" do
    before { payload["data"]["type"] = "other" }

    it_behaves_like "an invalid payload"
  end

  %w[format createdAt environment flags].each do |field|
    context "without #{field}" do
      before { attributes.delete(field) }

      it_behaves_like "an invalid payload"
    end
  end

  context "without the environment name" do
    before { attributes["environment"] = {} }

    it_behaves_like "an invalid payload"
  end

  context "when flags is not an object" do
    before { attributes["flags"] = [] }

    it_behaves_like "an invalid payload"
  end
end
