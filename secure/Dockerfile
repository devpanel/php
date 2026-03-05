ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# Set user as root to avoid access denied
USER root
WORKDIR /home/root

# Install mod security
ARG CORERULESET_VERSION="3.3.5"
RUN apt update -y && apt -y install libapache2-mod-security2
RUN rm -rf /usr/share/modsecurity-crs
RUN wget -O /tmp/modsecurity-crs.zip https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CORERULESET_VERSION}.zip
RUN unzip /tmp/modsecurity-crs.zip -d /usr/share/
RUN mv /usr/share/coreruleset-${CORERULESET_VERSION} /usr/share/modsecurity-crs

#Config mod_security
COPY templates/modsecurity.conf /etc/modsecurity/modsecurity.conf
COPY templates/crs-setup.conf /usr/share/modsecurity-crs/crs-setup.conf
COPY templates/security2.conf  /etc/apache2/mods-available/security2.conf

# PHP 7.4 and 8.0 use Debian 11 which ships mod_security 2.9.3; that version
# does not support the REQUEST-922-MULTIPART-ATTACK rule bundled with CRS 3.3.x.
ARG REMOVE_MULTIPART_RULE=false
RUN if [ "$REMOVE_MULTIPART_RULE" = "true" ]; then \
      rm /usr/share/modsecurity-crs/rules/REQUEST-922-MULTIPART-ATTACK.conf; \
    fi

# Revert back to normal user
USER ${USER}
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh" ]
