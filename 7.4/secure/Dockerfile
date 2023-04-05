FROM devpanel/php:7.4-base

ARG MODSECURITY_VERSION=v3.0.4

COPY templates /templates

# Download LibModsecurity 
RUN wget https://github.com/SpiderLabs/ModSecurity/releases/download/${MODSECURITY_VERSION}/modsecurity-${MODSECURITY_VERSION}.tar.gz

# Extract the Downloaded File
RUN tar xzf modsecurity-${MODSECURITY_VERSION}.tar.gz && rm -rf modsecurity-${MODSECURITY_VERSION}.tar.gz

# Compile and Install LibModsecurity
RUN cd modsecurity-${MODSECURITY_VERSION} && \
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

RUN cd ~/ModSecurity-apache && \
	./autogen.sh && \
	./configure --with-libmodsecurity=/usr/local/modsecurity/ && \
	make && \
	make install

# Load the Apache ModSecurity Connector Module
RUN echo "LoadModule security3_module /usr/lib/apache2/modules/mod_security3.so" >> /etc/apache2/apache2.conf

# Configure ModSecurity
RUN mkdir /etc/apache2/modsecurity.d && \
	cp modsecurity-${MODSECURITY_VERSION}/modsecurity.conf-recommended /etc/apache2/modsecurity.d/modsecurity.conf && \
	cp modsecurity-${MODSECURITY_VERSION}/unicode.mapping /etc/apache2/modsecurity.d/ && \
	sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/apache2/modsecurity.d/modsecurity.conf

RUN cp /templates/modsec_rules.conf /etc/apache2/modsecurity.d/

# Install OWASP ModSecurity Core Rule Set (CRS) on Ubuntu
RUN git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /etc/apache2/modsecurity.d/owasp-crs && \
	cp /etc/apache2/modsecurity.d/owasp-crs/crs-setup.conf.example /etc/apache2/modsecurity.d/owasp-crs/crs-setup.conf
