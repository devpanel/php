ARG BASE_IMAGE=devpanel/php:8.1-secure
FROM ${BASE_IMAGE}

ENV VARNISH_SIZE 100M

USER root

RUN apt install lsb-release curl gpg -y
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
