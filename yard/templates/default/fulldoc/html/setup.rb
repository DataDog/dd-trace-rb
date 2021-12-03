def generate_public_api_list
  @list_title = "Public API"
  @list_type = "public_api"
  verifier = Verifier.new('@public_api')

  @items = public_api_methods(verifier)
  @items += public_api_classes(verifier)

  @items.sort_by! { |m| m.name.to_s.downcase }

  generate_list_contents # YARD method at 'templates/default/fulldoc/html/setup.rb'
end

def public_api_methods(verifier)
  methods = Registry.all(:method)
  methods = run_verifier(methods) # Run global verifier
  verifier.run(methods)
end

def public_api_classes(verifier)
  classes = options.objects
  classes = run_verifier(classes) # Run global verifier
  verifier.run(classes)
end
