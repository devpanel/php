FROM devpanel/php:8.1-secure

ENV VARNISH_SIZE 100M

USER root

RUN apt install lsb-release curl gpg -y
RUN curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
RUN apt-get update
RUN apt-get install redis  supervisor -y

COPY scripts/redis-start.sh /scripts/redis-start.sh

COPY supervisor/supervisor.conf /etc/supervisor/conf.d/supervisor.conf


USER $USER
WORKDIR ${APP_ROOT}

CMD ["sudo", "-E", "/usr/bin/supervisord"]
