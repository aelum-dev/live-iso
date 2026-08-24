# syntax=docker/dockerfile:1
#
# AestheticOS Build Environment
# Arch Linux with archiso, makepkg, and all ISO build tools
#

FROM archlinux:base-devel

ENV TERM=xterm
ENV MAKEFLAGS="-j$(nproc)"

# Install build dependencies in a single layer
RUN pacman -Syu --noconfirm --disable-sandbox \
    && pacman -S --noconfirm --disable-sandbox \
        archiso \
        pacman \
        curl \
        jq \
        fakeroot \
        patch \
        xz \
        squashfs-tools \
        xorriso \
        dosfstools \
        btrfs-progs \
        syslinux \
        grub \
    && pacman -Sc --noconfirm

# Copy build scripts into the image
COPY docker/build-scripts/ /build-scripts/
RUN chmod +x /build-scripts/*.sh

WORKDIR /project

CMD ["bash", "/build-scripts/run-all.sh"]
