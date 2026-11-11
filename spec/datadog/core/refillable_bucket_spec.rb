require "spec_helper"

require "datadog/core/refillable_bucket"

RSpec.describe Datadog::Core::RefillableBucket do
  describe "construction" do
    it "is defined by the including classes" do
      aggregate_failures do
        expect(described_class.public_instance_methods(false)).not_to include(:initialize)
        expect(described_class.private_instance_methods(false)).not_to include(:initialize)
      end
    end
  end
end
