def stylesheets
  # Load the existing stylesheets while appending the custom one
  super + %w(css/datadog.css)
end
