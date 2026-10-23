# Tierwise CLI image: the fat JAR on a JRE 25 base, running as a non-root user.
#
# Build from the repository root, because the build context needs java/, presets/ and spec/data/:
#   docker build --file docker/Dockerfile --tag tierwise:local .
#
# Base images are pinned by digest (the digest decides; the tag is for humans). Docker/README.md explains
# how to read and update them.

# Build stage: the Maven Wrapper builds the fat JAR of the CLI on JDK 25 (ADR 0021, amended); the JARs target Java 17.
FROM eclipse-temurin:25-jdk-noble@sha256:ba0f0e1a33864105e1d454e88105c617ab40f71062db1f306bf58be32a3f8e5e AS build

# tierwise-core reads the built-in presets and the IANA zone names from ../../presets and ../../spec/data
# (see java/tierwise-core/pom.xml), so they are copied to the same relative places under /src.
COPY presets /src/presets
COPY spec/data/tz-names.txt /src/spec/data/tz-names.txt
COPY java /src/java

WORKDIR /src/java
# The Maven Wrapper needs unzip: without it, it switches to the .tar.gz distribution, whose checksum is not the
# one pinned in maven-wrapper.properties, and stops. The JDK image ships curl and wget but not unzip.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends unzip \
 && rm -rf /var/lib/apt/lists/*
# clean drops any target/ directory copied from a local build. Tests run in CI, not in the image build.
RUN set -eu; \
    chmod 0755 ./mvnw; \
    ./mvnw -B -ntp -DskipTests -pl tierwise-cli -am clean package; \
    jars=$(ls tierwise-cli/target/tierwise-cli-*-all.jar); \
    test "$(printf '%s\n' "$jars" | wc -l)" -eq 1; \
    mkdir -p /out; \
    cp "$jars" /out/tierwise.jar

# Runtime stage: a JRE only, with a fixed non-root user.
FROM eclipse-temurin:25-jre-noble@sha256:3f2223fe04b750aa5a8179e29b5c9a1ddf7665fc9bb08bfe11ad01d143bc13a5 AS runtime

LABEL org.opencontainers.image.title="tierwise" \
      org.opencontainers.image.description="Tierwise command line: init, validate, lint, test, compile, codegen, explain" \
      org.opencontainers.image.licenses="Apache-2.0"

# A fixed numeric UID lets a platform verify that the container does not run as root (see USER below).
RUN groupadd --system --gid 10001 tierwise \
 && useradd --system --uid 10001 --gid tierwise --no-create-home --shell /usr/sbin/nologin tierwise \
 && mkdir -p /opt/tierwise /work \
 && chown tierwise:tierwise /work

COPY --from=build /out/tierwise.jar /opt/tierwise/tierwise.jar

# The `tierwise` command: the fat JAR on the JRE's java launcher, with the arguments passed through.
RUN printf '%s\n' '#!/bin/sh' 'exec java -jar /opt/tierwise/tierwise.jar "$@"' > /usr/local/bin/tierwise \
 && chmod 0755 /usr/local/bin/tierwise

WORKDIR /work
USER 10001:10001
ENTRYPOINT ["tierwise"]
CMD ["--help"]
