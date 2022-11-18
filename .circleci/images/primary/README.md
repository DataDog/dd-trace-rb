# Dockerfiles used for testing and development

This folder contains Dockerfiles for all versions of Ruby used in the testing and development of dd-trace-rb.

## Multi-arch images

Images marked with a "# This image supports multiple platforms" are able to be built for both amd64 (x86_64) and
arm64 (aarch64) Linux.

Here's an example of building the Ruby 3.1 image:

```bash
# To build and push the image (update tag as needed):
$ docker buildx build . --platform linux/amd64,linux/arm64/v8 -f Dockerfile-3.1.1 -t ghcr.io/datadog/dd-trace-rb:3.1.1-dd --push
```
