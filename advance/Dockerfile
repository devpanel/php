# 'BASE_IMAGE' defaults to 'base-image' which matches the named context
# provided by Docker Bake (contexts.base-image = "target:{v}-secure").
ARG BASE_IMAGE=base-image
FROM ${BASE_IMAGE}

ENV VARNISH_SIZE 100M
ENV DEBIAN_FRONTEND=noninteractive

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends lsb-release curl gpg \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
RUN apt-get update \
	&& apt-get install -y --no-install-recommends redis supervisor \
	&& rm -rf /var/lib/apt/lists/*

COPY scripts/redis-start.sh /scripts/redis-start.sh

COPY supervisor/supervisor.conf /etc/supervisor/conf.d/supervisor.conf


USER $USER
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/usr/bin/supervisord"]
