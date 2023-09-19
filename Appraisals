lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

module DisableBundleCheck
  def check_command
    ['bundle', 'exec', 'false']
  end
end

::Appraisal::Appraisal.prepend(DisableBundleCheck) if ['true', 'y', 'yes', '1'].include?(ENV['APPRAISAL_SKIP_BUNDLE_CHECK'])

alias original_appraise appraise

REMOVED_GEMS = {
  :check => [
    'rbs',
    'steep',
  ],
}

def appraise(group, &block)
  # Specify the environment variable APPRAISAL_GROUP to load only a specific appraisal group.
  if ENV['APPRAISAL_GROUP'].nil? || ENV['APPRAISAL_GROUP'] == group
    original_appraise(group) do
      instance_exec(&block)

      REMOVED_GEMS.each do |group_name, gems|
        group(group_name) do
          gems.each do |gem_name|
            # appraisal 2.2 doesn't have remove_gem, which applies to ruby 2.1 and 2.2
            remove_gem gem_name if respond_to?(:remove_gem)
          end
        end
      end
    end
  end
end

ruby_runtime = if defined?(RUBY_ENGINE_VERSION)
                 "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
               else
                 "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
               end

instance_eval IO.read("appraisal/#{ruby_runtime}.rb")

appraisals.each do |appraisal|
  appraisal.name.prepend("#{ruby_runtime}-")
end

# vim: ft=ruby
