FROM debian:bookworm

ARG rgrc_VERSION
ARG BUILD_VERSION
ARG FULL_VERSION
ARG ARCH
ARG RGRC_RELEASE

RUN mkdir -p /output/usr/bin
RUN mkdir -p /output/etc
RUN mkdir -p /output/usr/share/rgrc
RUN mkdir -p /output/usr/share/doc/rgrc
RUN mkdir -p /output/usr/share/man/man1
RUN mkdir -p /output/usr/share/bash-completion/completions
RUN mkdir -p /output/usr/share/fish/vendor_completions.d
RUN mkdir -p /output/usr/share/zsh/vendor-completions
RUN mkdir -p /output/DEBIAN

COPY ${RGRC_RELEASE}/rgrc /output/usr/bin/
COPY rgrc-extras/rgrc.conf /output/etc/
COPY rgrc-extras/share/ /output/usr/share/rgrc/
COPY rgrc-extras/rgrc.1 /output/usr/share/man/man1/
COPY rgrc-extras/completions/rgrc /output/usr/share/bash-completion/completions/
COPY rgrc-extras/completions/rgrc.fish /output/usr/share/fish/vendor_completions.d/
COPY rgrc-extras/completions/_rgrc /output/usr/share/zsh/vendor-completions/
RUN chmod 755 /output/usr/bin/rgrc
RUN chmod 644 /output/etc/rgrc.conf /output/usr/share/rgrc/* /output/usr/share/man/man1/rgrc.1
RUN gzip -9n /output/usr/share/man/man1/*.1
COPY output/DEBIAN/control /output/DEBIAN/
COPY output/DEBIAN/conffiles /output/DEBIAN/
COPY output/DEBIAN/postinst /output/DEBIAN/postinst
RUN chmod 755 /output/DEBIAN/postinst
COPY output/copyright /output/usr/share/doc/rgrc/
COPY output/changelog.Debian /output/usr/share/doc/rgrc/
COPY output/README.md /output/usr/share/doc/rgrc/
RUN chmod 644 /output/usr/share/doc/rgrc/* /output/usr/share/bash-completion/completions/rgrc /output/usr/share/fish/vendor_completions.d/rgrc.fish /output/usr/share/zsh/vendor-completions/_rgrc

RUN sed -i "s/FULL_VERSION/$FULL_VERSION/" /output/usr/share/doc/rgrc/changelog.Debian
RUN sed -i "s/rgrc_VERSION/$rgrc_VERSION/" /output/DEBIAN/control
RUN sed -i "s/BUILD_VERSION/$BUILD_VERSION/" /output/DEBIAN/control
RUN sed -i "s/SUPPORTED_ARCHITECTURES/$ARCH/" /output/DEBIAN/control

RUN dpkg-deb -Zxz --build /output /rgrc_${FULL_VERSION}.deb
