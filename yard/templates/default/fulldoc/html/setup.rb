# List all classes, modules, and methods that are part of the public API
def generate_public_api_list
  @list_title = 'Public API'
  @list_type = 'public_api'

  # Matches nodes with @public_api YARD doc tag
  verifier = Verifier.new('@public_api')

  @items = public_api_methods(verifier)
  @items += public_api_classes(verifier)

  @items.sort_by! { |m| m.name.to_s.downcase }

  generate_list_contents # built-in YARD method at 'templates/default/fulldoc/html/setup.rb'
end

def public_api_methods(verifier)
  methods = Registry.all(:method)
  methods = run_verifier(methods) # Run global YARD verifier, in case one is configured
  verifier.run(methods)
end

def public_api_classes(verifier)
  classes = options.objects
  classes = run_verifier(classes) # Run global YARD verifier, in case one is configured
  verifier.run(classes)
end
