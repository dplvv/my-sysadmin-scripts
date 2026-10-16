FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 procps coreutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www
ENV LOG_FILE=/var/www/monitor.log

COPY script.sh entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/script.sh /usr/local/bin/entrypoint.sh

EXPOSE 8080
CMD ["/usr/local/bin/entrypoint.sh"]
