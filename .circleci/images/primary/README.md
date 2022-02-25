# Dockerfiles used for testing and development

This folder contains Dockerfiles for all versions of Ruby used in the testing and development of dd-trace-rb.

## Multiplatform builds

Images marked with a "# This image supports multiple platforms" are able to be built for both amd64 (x86_64) and
arm64 (aarch64) Linux.

Here's an example of building the Ruby 3.1 image:

```bash
# To build and push the image (update tag as needed):
$ docker buildx build . --platform linux/amd64,linux/arm64/v8 -f Dockerfile-3.1.1 -t ivoanjo/docker-library:ddtrace_rb_3_1_1 --push

# The tag created will automatically contain both architectures. To additionally create an
# architecture-specific tag, I needed to do the following (sha is the specific image)
$ docker pull ivoanjo/docker-library:ddtrace_rb_3_1_1@sha256:56402a1c5e522b669965db4600f1a4fa035f6e3597d098ec808e77192c4238fd
$ docker tag ivoanjo/docker-library@sha256:56402a1c5e522b669965db4600f1a4fa035f6e3597d098ec808e77192c4238fd ivoanjo/docker-library:ddtrace_rb_3_1_1_amd64
$ docker push ivoanjo/docker-library:ddtrace_rb_3_1_1_amd64
```
