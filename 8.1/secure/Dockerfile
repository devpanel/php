FROM devpanel/php:8.1-base


# Set user as root to avoid access denied
USER root
WORKDIR /home/root

ARG MODSECURE_VERSION="v3.0.4"

# Download LibModsecurity
RUN wget https://github.com/SpiderLabs/ModSecurity/releases/download/${MODSECURE_VERSION}/modsecurity-${MODSECURE_VERSION}.tar.gz

# Extract the Downloaded File
RUN tar xzf modsecurity-${MODSECURE_VERSION}.tar.gz && rm -rf modsecurity-${MODSECURE_VERSION}.tar.gz

# Compile and Install LibModsecurity
RUN  --mount=type=cache,target=/var/cache/mod_security_${MODSECURE_VERSION} \
	cd modsecurity-${MODSECURE_VERSION} && \
	./build.sh && ./configure && \
	make && make install

# Install ModSecurity-Apache Connector
RUN cd ~ && git clone https://github.com/SpiderLabs/ModSecurity-apache

# Install dependencies
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y \
    apache2-dev flex bison doxygen \
    libyajl-dev ssdeep liblua5.2-dev libtool dh-autoreconf \
    libcurl4-gnutls-dev libxml2 libpcre++-dev libxml2-dev

RUN --mount=type=cache,target=/var/cache/mod_security_apache_${MODSECURE_VERSION} \
	cd ~/ModSecurity-apache && \
	./autogen.sh && \
	./configure --with-libmodsecurity=/usr/local/modsecurity/ && \
	make && \
	make install

# Configure ModSecurity
RUN mkdir /etc/apache2/modsecurity.d && \
	cp modsecurity-${MODSECURE_VERSION}/modsecurity.conf-recommended /etc/apache2/modsecurity.d/modsecurity.conf && \
	cp modsecurity-${MODSECURE_VERSION}/unicode.mapping /etc/apache2/modsecurity.d/

COPY templates/modsecurity.conf /etc/apache2/modsecurity.d/
COPY templates/modsec_rules.conf /etc/apache2/modsecurity.d/

# Install OWASP ModSecurity Core Rule Set (CRS) on Ubuntu
RUN git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /etc/apache2/modsecurity.d/owasp-crs && \
	cp /etc/apache2/modsecurity.d/owasp-crs/crs-setup.conf.example /etc/apache2/modsecurity.d/owasp-crs/crs-setup.conf

# Revert back to normal user
USER ${USER}
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh" ]
