# Final secure image: extends the secure-intermediate (mod_security already
# installed).  No version-specific changes needed for PHP 8.1+.
# 'BASE_IMAGE' defaults to 'secure-intermediate' which matches the named
# context provided by Docker Bake.
ARG BASE_IMAGE=secure-intermediate
FROM ${BASE_IMAGE}

USER ${USER}
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/bin/bash", "/scripts/apache-start.sh"]
