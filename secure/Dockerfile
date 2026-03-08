# Intermediate stage: installs mod_security on top of a base image.
# 'BASE_IMAGE' defaults to 'base-image' which matches the named context
# provided by Docker Bake (contexts.base-image = "target:{v}-base").
# Never pushed to Docker Hub; cached in GitHub Actions cache.
ARG BASE_IMAGE=base-image
FROM ${BASE_IMAGE} AS secure-intermediate

USER root
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /home/root

ARG CORERULESET_VERSION="3.3.5"
RUN apt-get update -y && apt-get install -y --no-install-recommends libapache2-mod-security2 wget unzip \
    && rm -rf /var/lib/apt/lists/* \
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
