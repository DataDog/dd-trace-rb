# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/configuration/agentless_endpoint"
require "datadog/open_feature/configuration/flag_selection"

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
      expect(endpoint.uri.to_s).to eq(
        "https://ufc-server.ff-cdn.datadoghq.com/api/v2/feature-flagging/config/rules-based/server",
      )
      expect(endpoint).to be_managed
    end

    context "with a configured site and environment" do
      let(:site) { " US3.DATADOGHQ.COM " }
      let(:environment) { "staging/east" }

      it "normalizes the site and URL-encodes the raw environment" do
        expect(endpoint.uri.to_s).to eq(
          "https://ufc-server.ff-cdn.us3.datadoghq.com/api/v2/feature-flagging/config/rules-based/server?dd_env=staging%2Feast",
        )
      end
    end

    context "with a blank site" do
      let(:site) { "  " }

      it "uses the default site" do
        expect(endpoint.uri.host).to eq("ufc-server.ff-cdn.datadoghq.com")
      end
    end

    invalid_utf8_site = (+"datadoghq.\xFFcom").force_encoding(Encoding::UTF_8)
    ["https://datadoghq.com", "datadoghq.com/path", "datadoghq.com?target=other", "datadoghq.com#fragment",
      "datadoghq.com@other.example", "datadoghq.com:443", "data doghq.com", "datadoghq.\u212Aom",
      invalid_utf8_site].each do |invalid_site|
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
      expect(endpoint.uri.to_s).to eq(
        "http://localhost:8126/api/v2/feature-flagging/config/rules-based/server",
      )
      expect(endpoint).not_to be_managed
    end

    context "when the custom URL has a root path and query" do
      let(:base_url) { "https://example.test/?tenant=one" }

      it "appends the standard path and preserves the query" do
        expect(endpoint.uri.to_s).to eq(
          "https://example.test/api/v2/feature-flagging/config/rules-based/server?tenant=one",
        )
      end
    end

    context "when the custom URL has a non-root path" do
      let(:base_url) { "https://user:password@example.test/custom/path?dd_env=test" }
      let(:environment) { "ignored" }

      it "uses the URL verbatim without adding the environment" do
        expect(endpoint.uri.to_s).to eq("https://user:password@example.test/custom/path?dd_env=test")
      end
    end

    invalid_utf8_url = (+"https://example.test/\xFF").force_encoding(Encoding::UTF_8)
    [
      ["ftp://example.test/config", "Feature Flags agentless base URL must be an absolute HTTP or HTTPS URL; agentless delivery is disabled"],
      ["http:relative", "Feature Flags agentless base URL must be an absolute HTTP or HTTPS URL; agentless delivery is disabled"],
      ["relative/path", "Feature Flags agentless base URL must be an absolute HTTP or HTTPS URL; agentless delivery is disabled"],
      ["https://example.test/bad path", "Feature Flags agentless base URL contains whitespace; agentless delivery is disabled"],
      ["https://example.test/\u212A", "Feature Flags agentless base URL is invalid; agentless delivery is disabled"],
      [invalid_utf8_url, "Feature Flags agentless base URL is invalid; agentless delivery is disabled"],
    ].each do |invalid_url, expected_warning|
      context "with invalid URL #{invalid_url.inspect}" do
        let(:base_url) { invalid_url }

        it "rejects the URL without including it in the warning" do
          expect(endpoint).to be_nil
          expect(logger).to have_received(:warn).with(expected_warning)
        end
      end
    end
  end

  describe "#with_flag_selection" do
    subject(:selected_endpoint) { endpoint.with_flag_selection(selection) }

    let(:selection) do
      Datadog::OpenFeature::Configuration::FlagSelection.canonicalize(tags: ["team:a b"], key_patterns: ["checkout.*"])
    end

    it "does not send a selection from the endpoint as built" do
      expect(endpoint).not_to be_flag_selection_sent
    end

    context "with the managed endpoint and an environment" do
      let(:environment) { "my env" }

      it "appends the selection after the environment" do
        expect(selected_endpoint.uri.to_s).to eq(
          "https://ufc-server.ff-cdn.datadoghq.com/api/v2/feature-flagging/config/rules-based/server" \
            "?dd_env=my+env&selected_flag_tags=team%3Aa%20b&selected_flag_key_patterns=checkout.%2A",
        )
        expect(selected_endpoint).to be_managed
        expect(selected_endpoint).to be_flag_selection_sent
      end

      it "leaves the endpoint as built unchanged" do
        selected_endpoint

        expect(endpoint.uri.to_s).to eq(
          "https://ufc-server.ff-cdn.datadoghq.com/api/v2/feature-flagging/config/rules-based/server?dd_env=my+env",
        )
        expect(endpoint).not_to be_flag_selection_sent
      end
    end

    context "with the managed endpoint and no environment" do
      it "starts the query with the selection" do
        expect(selected_endpoint.uri.query).to eq(
          "selected_flag_tags=team%3Aa%20b&selected_flag_key_patterns=checkout.%2A",
        )
      end
    end

    context "with a custom endpoint carrying credentials and a query" do
      let(:base_url) { "https://user:pa%40ss@proxy.example.test/custom/path?dd_env=sys+tests&sig=a%2Fb" }

      it "keeps the credentials and the query and appends the selection" do
        expect(selected_endpoint.uri.to_s).to eq(
          "https://user:pa%40ss@proxy.example.test/custom/path?dd_env=sys+tests&sig=a%2Fb" \
            "&selected_flag_tags=team%3Aa%20b&selected_flag_key_patterns=checkout.%2A",
        )
        expect(selected_endpoint).not_to be_managed
      end
    end

    context "with a custom endpoint without a query" do
      let(:base_url) { "http://localhost:8126" }

      it "appends the selection as the query" do
        expect(selected_endpoint.uri.to_s).to eq(
          "http://localhost:8126/api/v2/feature-flagging/config/rules-based/server" \
            "?selected_flag_tags=team%3Aa%20b&selected_flag_key_patterns=checkout.%2A",
        )
      end
    end

    context "near the request URL limit" do
      let(:base_url) { "https://proxy.example.test/ufc" }
      let(:wide_tags) { Array.new(13) { |index| format("%02d", index) + "\u00E9" * 99 } }

      def selection_with_url_bytes(url_bytes)
        tags = wide_tags + ["x"]
        padding = url_bytes - endpoint.with_flag_selection(
          Datadog::OpenFeature::Configuration::FlagSelection.canonicalize(tags: tags),
        ).uri.to_s.bytesize
        Datadog::OpenFeature::Configuration::FlagSelection.canonicalize(tags: wide_tags + ["x" * (1 + padding)])
      end

      it "measures the whole URL after percent-encoding and allows 8192 bytes" do
        selected = endpoint.with_flag_selection(selection_with_url_bytes(8192))

        expect(selected.uri.to_s.bytesize).to eq(8192)
        expect(selected).to be_flag_selection_sent
      end

      it "returns nil above 8192 bytes" do
        expect(endpoint.with_flag_selection(selection_with_url_bytes(8193))).to be_nil
      end
    end
  end

  describe "#origin" do
    context "with the managed endpoint" do
      let(:environment) { "prod" }

      it "drops the path and environment query" do
        expect(endpoint.origin).to eq("https://ufc-server.ff-cdn.datadoghq.com")
      end
    end

    context "with a custom endpoint carrying credentials, a path, and a query" do
      let(:base_url) { "http://user:token@flags.example.test:8080/signed-path/ufc?sig=secret" }

      it "keeps only the scheme, host, and non-default port" do
        expect(endpoint.origin).to eq("http://flags.example.test:8080")
      end
    end

    context "with a custom endpoint on the default port" do
      let(:base_url) { "https://flags.example.test:443/ufc" }

      it "omits the port" do
        expect(endpoint.origin).to eq("https://flags.example.test")
      end
    end
  end
end
