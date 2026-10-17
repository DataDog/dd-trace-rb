require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/grape/endpoint"

RSpec.describe Datadog::Tracing::Contrib::Grape::Endpoint do
  describe ".api_view" do
    subject(:api_view) { described_class.send(:api_view, api) }

    context "when api inherits from Grape::API::Instance and responds to base" do
      let(:api) do
        stub_const("Grape::API::Instance", Class.new)
        stub_const(
          "TestAPI",
          Class.new(Grape::API::Instance) do
            def self.base
              "TestAPIBase"
            end
          end
        )
      end

      it "returns the base class name" do
        expect(api_view).to eq("TestAPIBase")
      end
    end

    # This test covers Grape < 1.2.0 where the API is an Grape::API::Instance and not a class,
    # as well as Grape >= 2.3.0 where the base attr_reader was removed
    # See: https://github.com/ruby-grape/grape/commit/98214705fb61e3e90583bd3ad2b9889daa1bc794
    context "when api inherits from Grape::API::Instance but does not respond to base" do
      let(:api) do
        stub_const("Grape::API::Instance", Class.new)
        stub_const("TestAPIWithoutBase", Class.new(Grape::API::Instance))
      end

      it "returns the api class name via to_s" do
        expect(api_view).to eq("TestAPIWithoutBase")
      end
    end
  end

  describe ".endpoint_api" do
    subject(:endpoint_api) { described_class.send(:endpoint_api, endpoint) }

    let(:api) { Class.new }

    context "when options carries :for (Grape 3 and earlier)" do
      let(:endpoint) { double("Grape::Endpoint", options: {for: api}) }

      it "reads the API off options[:for]" do
        expect(endpoint_api).to be(api)
      end
    end

    context "when options has no :for (Grape 4 and later)" do
      let(:endpoint) { double("Grape::Endpoint", options: {}, api: api) }

      it "reads the API off #api" do
        expect(endpoint_api).to be(api)
      end
    end

    context "when options carries :for and the endpoint also responds to #api" do
      let(:endpoint) { double("Grape::Endpoint", options: {for: api}, api: Class.new) }

      it "prefers options[:for]" do
        expect(endpoint_api).to be(api)
      end
    end
  end

  describe ".endpoint_request_method" do
    subject(:request_method) { described_class.send(:endpoint_request_method, endpoint) }

    context "when the options Hash carries :method (Grape 3 and earlier)" do
      let(:endpoint) do
        double("Grape::Endpoint", options: {method: ["GET"]}, routes: [double("Route", request_method: "POST")])
      end

      it "prefers the options Hash, leaving existing versions unchanged" do
        expect(request_method).to eq("GET")
      end
    end

    context "when the options Hash does not carry :method (Grape 4 and later)" do
      let(:endpoint) { double("Grape::Endpoint", options: {}, routes: [double("Route", request_method: "PATCH")]) }

      it "reads the verb off the first route" do
        expect(request_method).to eq("PATCH")
      end
    end

    context "when the endpoint has no routes" do
      let(:endpoint) { double("Grape::Endpoint", options: {}, routes: []) }

      it "returns nil rather than raising" do
        expect(request_method).to be_nil
      end
    end
  end

  describe ".endpoint_expand_path" do
    subject(:path) { described_class.send(:endpoint_expand_path, endpoint) }

    # No example for the pre-Grape-4 branch: it is unchanged, and its join calls
    # ActiveSupport's String#blank?, which this spec does not load.
    context "when the options Hash does not carry :path (Grape 4 and later)" do
      let(:endpoint) do
        double(
          "Grape::Endpoint",
          options: {},
          routes: [double("Route", namespace: "/api/v1", path: "/api/v1/widgets(.json)")]
        )
      end

      it "uses the compiled route path, which already carries the namespace" do
        expect(path).to eq("/api/v1/widgets")
      end

      it "strips a :format segment too" do
        allow(endpoint.routes.first).to receive(:path).and_return("/api/v1/widgets/:id(.:format)")
        expect(path).to eq("/api/v1/widgets/:id")
      end
    end

    context "when the endpoint has no routes" do
      let(:endpoint) { double("Grape::Endpoint", options: {}, routes: []) }

      it "returns the root path rather than raising" do
        expect(path).to eq("/")
      end
    end

    context "when the route has no path" do
      let(:endpoint) { double("Grape::Endpoint", options: {}, routes: [double("Route", path: nil)]) }

      it "returns the root path rather than raising" do
        expect(path).to eq("/")
      end
    end

    context "when the options Hash carries an empty :path" do
      let(:endpoint) do
        double("Grape::Endpoint", options: {path: []}, routes: [double("Route", path: "/widgets(.json)")])
      end

      it "uses the compiled route path rather than resolving to the namespace alone" do
        expect(path).to eq("/widgets")
      end
    end
  end
end
