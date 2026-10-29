# Build environment for the cepheus port on a Linux host: pmbootstrap, the kernel tree and the DT loop, plus the
# phone-side tools (fastboot, ssh, tinyproxy), without installing any of it on the host.
# Use it through scripts/docker-env, which builds this image and runs it with the flags it needs (docs/docker.md).
# Same base as the macOS OrbStack VM (setup-host.sh): Alpine edge.
FROM alpine:edge

RUN apk add --no-cache \
	bash coreutils curl git openssl python3 \
	doas su-exec \
	losetup multipath-tools util-linux \
	build-base bc bison dtc elfutils-dev flex linux-headers openssl-dev perl \
	clang lld llvm \
	android-tools openssh-client tinyproxy netcat-openbsd \
	rsync zstd

# pmbootstrap refuses to run as root, and files it writes into the bind-mounted repo (apks/, images/) should belong to
# the host user: scripts/docker-env passes the repo owner's UID/GID.
ARG UID=1000
ARG GID=1000
RUN getent group "$GID" >/dev/null || addgroup -g "$GID" builder; \
	adduser -D -u "$UID" -G "$(getent group "$GID" | cut -d: -f1)" -s /bin/bash builder; \
	echo 'permit nopass builder' > /etc/doas.d/builder.conf; chmod 600 /etc/doas.d/builder.conf
LABEL cepheus.uid="$UID" cepheus.gid="$GID"

# setup-host.sh installs pmbootstrap to ~/.local/share/pmbootstrap and links it here
ENV PATH=/home/builder/.local/bin:$PATH

COPY entrypoint.sh /usr/local/sbin/cepheus-entrypoint
ENTRYPOINT ["/usr/local/sbin/cepheus-entrypoint"]
CMD ["bash", "-l"]
