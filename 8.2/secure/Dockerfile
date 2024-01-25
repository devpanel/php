FROM devpanel/php:8.2-base

# Set user as root to avoid access denied
USER root
WORKDIR /home/root

# Install mod security
ARG CORERULSET_VERSION="3.3.5"
RUN apt update -y && apt -y install libapache2-mod-security2
RUN rm -rf /usr/share/modsecurity-crs
RUN wget -O /tmp/modsecurity-crs.zip https://github.com/coreruleset/coreruleset/archive/refs/tags/v${CORERULSET_VERSION}.zip
RUN unzip /tmp/modsecurity-crs.zip -d /usr/share/
RUN mv /usr/share/coreruleset-${CORERULSET_VERSION} /usr/share/modsecurity-crs

#Config mod_security
COPY templates/modsecurity.conf /etc/modsecurity/modsecurity.conf
COPY templates/crs-setup.conf /usr/share/modsecurity-crs/crs-setup.conf
COPY templates/security2.conf  /etc/apache2/mods-available/security2.conf

# Revert back to normal user
USER ${USER}
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh" ]
