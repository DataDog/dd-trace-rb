# template.rb

run_bundle

generate(:scaffold, "person name:string")
route "root to: 'people#index'"
rails_command("db:migrate")

initializer 'bloatlol.rb', <<-CODE
  class Object
    def not_nil?
      !nil?
    end
 
    def not_blank?
      !blank?
    end
  end
CODE

file 'app/components/foo.rb', <<-CODE
  class Foo
  end
CODE

after_bundle do
  git :init
  git add: "."
  git commit: %Q{ -m 'Initial commit' }
end
