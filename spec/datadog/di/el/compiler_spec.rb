require "spec_helper"
require_relative "../spec_helper"
require "datadog/di/el"

RSpec.describe Datadog::DI::EL::Compiler do
  di_test

  let(:compiler) { described_class.new }

  describe "#redaction_identifier" do
    [
      ["local reference", {"ref" => "password"}, "password"],
      ["instance variable reference", {"ref" => "@password"}, "@password"],
      ["member access", {"getmember" => [{"ref" => "obj"}, "password"]}, "password"],
      ["string index", {"index" => [{"ref" => "h"}, "password"]}, "password"],
      ["numeric index", {"index" => [{"ref" => "arr"}, 0]}, nil],
      ["non-reference operation", {"len" => {"ref" => "password"}}, nil],
      ["non-hash ast", "password", nil],
      ["empty hash", {}, nil],
    ].each do |desc, ast, expected|
      context desc do
        it "returns #{expected.inspect}" do
          expect(compiler.redaction_identifier(ast)).to eq(expected)
        end
      end
    end
  end
end
