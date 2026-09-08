# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/configuration/agentless_endpoint"

RSpec.describe Datadog::OpenFeature::Configuration::AgentlessEndpoint do
  subject(:endpoint) do
    described_class.build(site: site, environment: environment, base_url: base_url, logger: logger)
  end

  let(:site) { "datadoghq.com" }
  let(:environment) { nil }
  let(:base_url) { nil }
  let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }

  context "when using the managed endpoint" do
    it "builds the default endpoint" do
      expect(endpoint&.uri&.to_s).to eq(
        "https://ufc-server.ff-cdn.datadoghq.com/api/v2/feature-flagging/config/rules-based/server"
      )
      expect(endpoint).to be_managed
    end

    context "with a configured site and environment" do
      let(:site) { " US3.DATADOGHQ.COM " }
      let(:environment) { "staging/east" }

      it "normalizes the site and URL-encodes the raw environment" do
        expect(endpoint&.uri&.to_s).to eq(
          "https://ufc-server.ff-cdn.us3.datadoghq.com/api/v2/feature-flagging/config/rules-based/server?dd_env=staging%2Feast"
        )
      end
    end

    context "with a blank site" do
      let(:site) { "  " }

      it "uses the default site" do
        expect(endpoint&.uri&.host).to eq("ufc-server.ff-cdn.datadoghq.com")
      end
    end

    ["https://datadoghq.com", "datadoghq.com/path", "datadoghq.com?target=other", "datadoghq.com#fragment",
      "datadoghq.com@other.example", "datadoghq.com:443", "data doghq.com"].each do |invalid_site|
      context "with invalid site #{invalid_site.inspect}" do
        let(:site) { invalid_site }

        it "rejects the site without including it in the warning" do
          expect(endpoint).to be_nil
          expect(logger).to have_received(:warn).with("Feature Flags site is invalid; agentless delivery is disabled")
        end
      end
    end
  end

  context "when using a custom endpoint" do
    let(:base_url) { "http://localhost:8126" }

    it "appends the standard path to an origin URL" do
      expect(endpoint&.uri&.to_s).to eq(
        "http://localhost:8126/api/v2/feature-flagging/config/rules-based/server"
      )
      expect(endpoint).not_to be_managed
    end

    context "when the custom URL has a root path and query" do
      let(:base_url) { "https://example.test/?tenant=one" }

      it "appends the standard path and preserves the query" do
        expect(endpoint&.uri&.to_s).to eq(
          "https://example.test/api/v2/feature-flagging/config/rules-based/server?tenant=one"
        )
      end
    end

    context "when the custom URL has a non-root path" do
      let(:base_url) { "https://user:password@example.test/custom/path?dd_env=test" }
      let(:environment) { "ignored" }

      it "uses the URL verbatim without adding the environment" do
        expect(endpoint&.uri&.to_s).to eq("https://user:password@example.test/custom/path?dd_env=test")
      end
    end

    ["ftp://example.test/config", "relative/path", "https://example.test/bad path"].each do |invalid_url|
      context "with invalid URL #{invalid_url.inspect}" do
        let(:base_url) { invalid_url }

        it "rejects the URL without including it in the warning" do
          expected_warning = if invalid_url.include?(" ")
            "Feature Flags agentless base URL contains whitespace; agentless delivery is disabled"
          else
            "Feature Flags agentless base URL must be an absolute HTTP or HTTPS URL; agentless delivery is disabled"
          end

          expect(endpoint).to be_nil
          expect(logger).to have_received(:warn).with(expected_warning)
        end
      end
    end
  end
end
