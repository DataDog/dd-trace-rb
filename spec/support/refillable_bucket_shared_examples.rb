RSpec.shared_examples "a refillable bucket validating constructor arguments" do
  context "with invalid rate" do
    let(:rate) { :bad }

    it "raises argument error" do
      expect { bucket }.to raise_error(ArgumentError, /rate must be a number/)
    end
  end

  context "with invalid max_tokens" do
    let(:max_tokens) { :bad }

    it "raises argument error" do
      expect { bucket }.to raise_error(ArgumentError, /max_tokens must be a number/)
    end
  end
end
