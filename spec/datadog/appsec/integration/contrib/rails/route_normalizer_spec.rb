# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/appsec/spec_helper"

require "action_dispatch"
require "datadog/appsec/route_normalizer"

RSpec.describe Datadog::AppSec::RouteNormalizer do
  def build_route(path_spec)
    allow(Devise).to receive(:configure_warden!) if defined?(Devise)

    route_set = ActionDispatch::Routing::RouteSet.new
    route_set.draw { get path_spec, to: "test#show" }
    route_set.routes.first
  end

  describe ".extract_normalized_route" do
    subject(:normalized_route) { described_class.extract_normalized_route(rack_env) }

    context "with Rails route object from Datadog key" do
      context "when route has a single named param" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/users/:id"),
            "action_dispatch.request.path_parameters" => {id: "42"},
            "PATH_INFO" => "/users/42",
          }
        end

        it { expect(normalized_route).to eq("/users/{id}") }
      end

      context "when route has optional format present in URL" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/posts/:id(.:format)"),
            "action_dispatch.request.path_parameters" => {id: "1", format: "json"},
            "PATH_INFO" => "/posts/1.json",
          }
        end

        it { expect(normalized_route).to eq("/posts/{id+format}") }
      end

      context "when route has optional format absent from URL" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/posts/:id(.:format)"),
            "action_dispatch.request.path_parameters" => {id: "1", format: nil},
            "PATH_INFO" => "/posts/1",
          }
        end

        it { expect(normalized_route).to eq("/posts/{id}") }
      end

      context "when route has optional format as Symbol default" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/posts/:id(.:format)"),
            "action_dispatch.request.path_parameters" => {id: "1", format: :json},
            "PATH_INFO" => "/posts/1",
          }
        end

        it { expect(normalized_route).to eq("/posts/{id}") }
      end

      context "when route has optional format as String default not in URL" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/posts/:id(.:format)"),
            "action_dispatch.request.path_parameters" => {id: "1", format: "json"},
            "PATH_INFO" => "/posts/1",
          }
        end

        it { expect(normalized_route).to eq("/posts/{id}") }
      end

      context "when route has nested optionals" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/archive(/:year(/:month(/:day)))"),
            "action_dispatch.request.path_parameters" => {year: "2024"},
            "PATH_INFO" => "/archive/2024",
          }
        end

        it { expect(normalized_route).to eq("/archive/{year}") }
      end

      context "when route has mixed static and dynamic text" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/mixed/user-:id"),
            "action_dispatch.request.path_parameters" => {id: "42"},
            "PATH_INFO" => "/mixed/user-42",
          }
        end

        it { expect(normalized_route).to eq("/mixed/{id}") }
      end

      context "when route has an optional group but no params" do
        let(:rack_env) do
          {
            "datadog.action_dispatch.route" => build_route("/foo(/bar)"),
            "action_dispatch.request.path_parameters" => {},
            "PATH_INFO" => "/foo/bar",
          }
        end

        it { expect(normalized_route).to eq("/foo") }
      end
    end

    context "with Rails native route key" do
      let(:rack_env) do
        {
          "action_dispatch.route" => build_route("/users/:id"),
          "action_dispatch.request.path_parameters" => {id: "42"},
          "PATH_INFO" => "/users/42",
        }
      end

      it { expect(normalized_route).to eq("/users/{id}") }
    end

    context "with Rails route_uri_pattern key" do
      context "when format is present in URL" do
        let(:rack_env) do
          {
            "action_dispatch.route_uri_pattern" => "/posts/:id(.:format)",
            "action_dispatch.request.path_parameters" => {id: "1", format: "json"},
            "PATH_INFO" => "/posts/1.json",
          }
        end

        it { expect(normalized_route).to eq("/posts/{id+format}") }
      end

      context "when path params disagree with request path" do
        let(:rack_env) do
          {
            "action_dispatch.route_uri_pattern" => "/books(/:category)",
            "action_dispatch.request.path_parameters" => {category: "fiction"},
            "PATH_INFO" => "/books",
          }
        end

        it { expect(normalized_route).to eq("/books") }
      end

      context "when route has an optional group without params" do
        let(:rack_env) do
          {
            "action_dispatch.route_uri_pattern" => "/foo(/bar)",
            "action_dispatch.request.path_parameters" => {},
            "PATH_INFO" => "/foo/bar",
          }
        end

        it { expect(normalized_route).to eq("/foo") }
      end
    end

    context "when request path has a mount prefix" do
      subject(:normalized_route) { described_class.extract_normalized_route(rack_env, prefix: "/api/v2") }

      let(:rack_env) do
        {
          "action_dispatch.route_uri_pattern" => "/users/:id(.:format)",
          "action_dispatch.request.path_parameters" => {id: "42", format: nil},
          "PATH_INFO" => "/api/v2/users/42",
        }
      end

      it { expect(normalized_route).to eq("/users/{id}") }
    end

    context "when Datadog key and Rails native key are both present" do
      let(:rack_env) do
        {
          "datadog.action_dispatch.route" => build_route("/from-tracer/:id"),
          "action_dispatch.route" => build_route("/from-rails/:id"),
          "action_dispatch.request.path_parameters" => {id: "42"},
          "PATH_INFO" => "/from-tracer/42",
        }
      end

      it { expect(normalized_route).to eq("/from-tracer/{id}") }
    end
  end
end
