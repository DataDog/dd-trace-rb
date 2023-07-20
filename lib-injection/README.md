# Host injection

The gitlab build pipeline ships pre-installed `ddtrace` deb and rpm packages.

Currently, we support

| Environment| version |
|---|---|
| Ruby  | `2.7`, `3.0`, `3.1`, `3.2`|
| OS    | Debian 10+ |
| Arch  | `amd64` |


### Packaging

In order to ship `ddtrace` and its dependencies as a pre-install package, we need a few tweaks in our build pipeline.

* Use multiple custom built Ruby images to build native extensions. Those images are based on Debian `buster` to support older distribution and Ruby is compiled as a static library with `--disbale-shared` option which disables the creation of shared libraries (also known as dynamic libraries or DLLs).
* Install `ffi` gem with its built-in `libffi` native extension instead of using system's `libffi`.
* After gem installation, the native extensions would be store in `extensions/x86_64-linux/3.2.0-static/`(see `Gem.extension_api_version`). We rename those directories to remove the `-static` suffix so user’s ruby can detect those  `.so` files and make sure files have read permission.

### Injection

The host inject script would add `ddtrace` to your Ruby on Rails application's `Gemfile` to [instrument your application](https://docs.datadoghq.com/tracing/trace_collection/dd_libraries/ruby/#rails-or-hanami-applications)).

* Bundler version must be >= 2.3
* Does not support vendoring gem ([Bundler's Deployment Mode](https://www.bundler.cn/man/bundle-install.1.html#DEPLOYMENT-MODE) or `BUNDLE_PATH`)



