AppSec WAF rules based on [appsec-event-rules](https://github.com/datadog/appsec-event-rules) builds

## How to update

In order to update rules, download `recommended.json` and `strict.json` of the desired version from [appsec-event-rules](https://github.com/datadog/appsec-event-rules) (example: [v1.13.3](https://github.com/DataDog/appsec-event-rules/tree/1.13.3/build))

You can store the following code as a `Rakefile` under `lib/datadog/appsec/assets/waf_rules`

```ruby
def download(filename)
  build_path = 'repos/DataDog/appsec-event-rules/contents/build'

  system("gh api #{build_path}/#{filename} --jq '.content' | base64 -d > #{filename}")
end

task default: :update

task :verify_dependencies do
  next if system('which gh 1>/dev/null')

  abort <<~MESSAGE
    \033[0;33mNOTE: To successfully execute that task make sure you have
          GitHub CLI installed and authenticated https://cli.github.com/\033[0m
  MESSAGE
end

desc 'Update recommended.json and strict.json to the latest version'
task update: :verify_dependencies do
  download('strict.json')
  download('recommended.json')

  puts "\033[0;32mSuccess!\033[0m"
end
```

And run the following command

> [!IMPORTANT]
> To run that command you will need to install GitHub CLI tool and authenticate it
> See: https://cli.github.com/ (or ddtool)


```console
$ bundle exec rake update
Success!
```
