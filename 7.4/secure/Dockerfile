# Final secure image: extends the secure-intermediate (mod_security already
# installed) with the PHP 7.4/8.0-specific tweak.
# 'BASE_IMAGE' defaults to 'secure-intermediate' which matches the named
# context provided by Docker Bake.
ARG BASE_IMAGE=secure-intermediate
FROM ${BASE_IMAGE} AS final

# PHP 7.4 and 8.0 ship Debian 11 with mod_security 2.9.3, which does not
# support the REQUEST-922-MULTIPART-ATTACK rule bundled with CRS 3.3.x.
RUN sudo rm /usr/share/modsecurity-crs/rules/REQUEST-922-MULTIPART-ATTACK.conf
