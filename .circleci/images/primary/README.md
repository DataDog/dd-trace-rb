# Dockerfiles used for testing and development

This folder contains Dockerfiles for all versions of Ruby used in the testing and development of dd-trace-rb.

## Multi-arch images

All images are able to be built for both `x86_64` (a.k.a `amd64`) and `aarch64` (a.k.a `arm64/v8`) Linux.

Here's an example of manually building Ruby 3.1 images:

```bash
# To build single-arch images locally (NEVER PUSH THESE!):
$ docker buildx build . --platform linux/x86_64 -f Dockerfile-3.1.1 -t ghcr.io/datadog/dd-trace-rb/ruby:3.1.1-dd
$ docker buildx build . --platform linux/aarch64 -f Dockerfile-3.1.1 -t ghcr.io/datadog/dd-trace-rb/ruby:3.1.1-dd

# To build AND push multi-arch images (but DON'T DO THAT IN GENERAL, unless e.g CI is down):
$ docker buildx build . --platform linux/x86_64,linux/aarch64 -f Dockerfile-3.1.1 -t ghcr.io/datadog/dd-trace-rb/ruby:3.1.1-dd --push
```
