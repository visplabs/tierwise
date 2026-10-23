# Tierwise server image: the executable Spring Boot JAR of tierwise-server on a JRE 25 base, running as a non-root user.
#
# Build from the repository root, because the build context needs java/, presets/ and spec/data/:
#   docker build --file docker/server.Dockerfile --tag tierwise-server:local .
#
# Base images are the same ones, pinned by the same digests, as in docker/Dockerfile (the digest decides; the tag is
# for humans). Update the digests in both files together. docker/README.md explains how.

# Build stage: the Maven Wrapper builds the executable JAR of the server on JDK 25 (ADR 0021, amended; ADR 0022).
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
# The spring-boot-maven-plugin attaches the runnable JAR with the classifier "exec".
RUN set -eu; \
    chmod 0755 ./mvnw; \
    ./mvnw -B -ntp -DskipTests -pl tierwise-server -am clean package; \
    jars=$(ls tierwise-server/target/tierwise-server-*-exec.jar); \
    test "$(printf '%s\n' "$jars" | wc -l)" -eq 1; \
    mkdir -p /out; \
    cp "$jars" /out/tierwise-server.jar

# Runtime stage: a JRE only, with a fixed non-root user.
FROM eclipse-temurin:25-jre-noble@sha256:3f2223fe04b750aa5a8179e29b5c9a1ddf7665fc9bb08bfe11ad01d143bc13a5 AS runtime

LABEL org.opencontainers.image.title="tierwise-server" \
      org.opencontainers.image.description="Tierwise control plane: stores bundle versions and serves bundles, /v1/resolve and /v1/decide" \
      org.opencontainers.image.licenses="Apache-2.0"

# A fixed numeric UID lets a platform verify that the container does not run as root (see USER below).
# /data is the default home of the filesystem bundle store; mount a volume there to keep bundles.
RUN groupadd --system --gid 10001 tierwise \
 && useradd --system --uid 10001 --gid tierwise --no-create-home --shell /usr/sbin/nologin tierwise \
 && mkdir -p /opt/tierwise /data \
 && chown tierwise:tierwise /data

COPY --from=build /out/tierwise-server.jar /opt/tierwise/tierwise-server.jar

# tierwise.server.filesystem.root, set through Spring Boot's environment binding. Its default is ./tierwise-data.
ENV TIERWISE_SERVER_FILESYSTEM_ROOT=/data

WORKDIR /data
USER 10001:10001
EXPOSE 8080
VOLUME ["/data"]

# The server accepts no token until an issuer or a JWK set is configured (java/tierwise-server/README.md), so pass
# --spring.security.oauth2.resourceserver.jwt.issuer-uri=... as arguments, or set the matching environment variable.
# Arguments after the image name go to Spring Boot. There is no HEALTHCHECK: the image has neither curl nor an
# actuator, and GET /openapi.yaml is the unauthenticated endpoint that a platform probe can use.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/opt/tierwise/tierwise-server.jar"]
