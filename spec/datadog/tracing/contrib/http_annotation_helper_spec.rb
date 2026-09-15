require "spec_helper"

require "datadog/tracing/contrib/http_annotation_helper"

RSpec.describe Datadog::Tracing::Contrib::HttpAnnotationHelper do
  let(:helper) { Class.new { include Datadog::Tracing::Contrib::HttpAnnotationHelper }.new }

  describe "#http_client_resource_name" do
    subject(:resource_name) { helper.http_client_resource_name(http_method, path) }

    let(:http_method) { "GET" }
    let(:path) { "/users/12345" }

    context "when quantization is disabled" do
      it { is_expected.to eq("GET") }

      context "and the method is lowercase" do
        let(:http_method) { "get" }

        it { is_expected.to eq("GET") }
      end
    end

    context "when quantization is enabled" do
      before do
        Datadog.configure { |c| c.tracing.http_client_resource_name_quantize = true }
      end

      it { is_expected.to eq("GET /users/?") }

      context "and the path carries a query string" do
        let(:path) { "/users/12345?sort_by=asc" }

        it { is_expected.to eq("GET /users/?") }
      end

      context "and the path is nil" do
        let(:path) { nil }

        it { is_expected.to eq("GET /") }
      end

      context "and the path has an invalid encoding" do
        let(:path) { "/users/\xFF" }

        before do
          expect(Datadog.logger).to receive(:error)
            .with(a_string_including("error building http client resource name"))
          expect(Datadog::Core::Telemetry::Logger).to receive(:report)
        end

        it { is_expected.to eq("GET") }
      end
    end
  end
end
