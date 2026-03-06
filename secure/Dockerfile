# Intermediate stage: installs mod_security on top of a base image.
# 'BASE_IMAGE' defaults to 'base-image' which matches the named context
# provided by Docker Bake (contexts.base-image = "target:{v}-base").
# Never pushed to Docker Hub; cached in GitHub Actions cache.
ARG BASE_IMAGE=base-image
FROM ${BASE_IMAGE}

USER root
WORKDIR /home/root

ARG CORERULESET_VERSION="3.3.5"
RUN apt update -y && apt -y install libapache2-mod-security2
RUN rm -rf /usr/share/modsecurity-crs
RUN wget -O /tmp/modsecurity-crs.zip \
      https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CORERULESET_VERSION}.zip
RUN unzip /tmp/modsecurity-crs.zip -d /usr/share/ \
    && mv /usr/share/coreruleset-${CORERULESET_VERSION} /usr/share/modsecurity-crs \
    && rm /tmp/modsecurity-crs.zip

COPY templates/modsecurity.conf /etc/modsecurity/modsecurity.conf
COPY templates/crs-setup.conf   /usr/share/modsecurity-crs/crs-setup.conf
COPY templates/security2.conf   /etc/apache2/mods-available/security2.conf
# USER, WORKDIR and CMD are set in the per-version {version}/secure/Dockerfile
