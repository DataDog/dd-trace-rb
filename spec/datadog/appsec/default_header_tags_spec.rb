# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/default_header_tags"
require "datadog/core/header_collection"

RSpec.describe Datadog::AppSec::DefaultHeaderTags do
  let(:span) { instance_double(Datadog::Tracing::SpanOperation, set_tag: nil) }

  describe ".tag_request" do
    before { described_class.tag_request(span, Datadog::Core::HeaderCollection.from_hash(headers)) }

    context "when a tracked request header is present" do
      let(:headers) { {"x-amzn-trace-id" => "trace-123"} }

      it { expect(span).to have_received(:set_tag).with("http.request.headers.x-amzn-trace-id", "trace-123") }
    end

    context "when an untracked request header is present" do
      let(:headers) { {"authorization" => "Bearer token"} }

      it { expect(span).not_to have_received(:set_tag) }
    end

    context "when the header name casing differs" do
      let(:headers) { {"X-Amzn-Trace-Id" => "trace-123"} }

      it { expect(span).to have_received(:set_tag).with("http.request.headers.x-amzn-trace-id", "trace-123") }
    end

    context "when the value is not a string" do
      let(:headers) { {"x-amzn-trace-id" => 42} }

      it { expect(span).to have_received(:set_tag).with("http.request.headers.x-amzn-trace-id", 42) }
    end
  end

  describe ".tag_response" do
    before { described_class.tag_response(span, Datadog::Core::HeaderCollection.from_hash(headers)) }

    context "when response headers are present" do
      let(:headers) { {"content-type" => "text/plain", "content-language" => "en-US"} }

      it "tags each present response header on the span" do
        aggregate_failures "response header tags" do
          expect(span).to have_received(:set_tag).with("http.response.headers.content-type", "text/plain")
          expect(span).to have_received(:set_tag).with("http.response.headers.content-language", "en-US")
        end
      end
    end

    context "when a response header is absent" do
      let(:headers) { {"content-type" => "text/plain"} }

      it { expect(span).not_to have_received(:set_tag).with("http.response.headers.content-language", anything) }
    end

    context "when the header name casing differs" do
      let(:headers) { {"Content-Type" => "text/plain"} }

      it { expect(span).to have_received(:set_tag).with("http.response.headers.content-type", "text/plain") }
    end

    context "when the value is not a string" do
      let(:headers) { {"content-length" => 42} }

      it { expect(span).to have_received(:set_tag).with("http.response.headers.content-length", "42") }
    end
  end
end
