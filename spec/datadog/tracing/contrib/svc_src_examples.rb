RSpec.shared_examples_for "tags _dd.svc_src" do |component|
  it "sets _dd.svc_src to '#{component}'" do
    expect(span.get_tag("_dd.svc_src")).to eq(component)
  end
end
