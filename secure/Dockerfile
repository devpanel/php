# Intermediate stage: installs mod_security on top of a base image.
# 'BASE_IMAGE' defaults to 'base-image' which matches the named context
# provided by Docker Bake (contexts.base-image = "target:{v}-base").
# Never pushed to Docker Hub; cached in GitHub Actions cache.
ARG BASE_IMAGE=base-image
FROM ${BASE_IMAGE} AS secure-intermediate

USER root
ARG DEBIAN_FRONTEND=noninteractive
WORKDIR /home/root

ARG CORERULESET_VERSION="3.3.5"
# Retry up to 3 times to handle transient apt mirror/network failures (e.g. connection
# resets mid-download). seq generates the sequence so i takes values 1, 2, 3 in turn.
RUN echo 'Dpkg::Use-Pty "0";' > /etc/apt/apt.conf.d/01dpkg-no-pty \
    && for i in $(seq 1 3); do \
      apt-get update -y \
        && apt-get install -y --no-install-recommends libapache2-mod-security2 wget unzip \
        && break \
      || { [ "$i" -lt 3 ] && sleep 5; }; \
    done \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/apt/apt.conf.d/01dpkg-no-pty \
    && rm -rf /usr/share/modsecurity-crs \
    && wget -O /tmp/modsecurity-crs.zip \
         https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CORERULESET_VERSION}.zip \
    && unzip /tmp/modsecurity-crs.zip -d /usr/share/ \
    && mv /usr/share/coreruleset-${CORERULESET_VERSION} /usr/share/modsecurity-crs \
    && rm /tmp/modsecurity-crs.zip

COPY templates/modsecurity.conf /etc/modsecurity/modsecurity.conf
COPY templates/crs-setup.conf   /usr/share/modsecurity-crs/crs-setup.conf
COPY templates/security2.conf   /etc/apache2/mods-available/security2.conf

USER ${USER}
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]

# Final stage: retag the intermediate as the pushed secure image for versions
# that need no per-version changes (8.1+).  Versions needing the multipart-rule
# fix (7.4 and 8.0) use their own per-version Dockerfile instead.
FROM secure-intermediate AS final
