FROM debian:bullseye-slim

ENV ARCH=amd64 \
    SEAFILE_HOME=/app
	
RUN apt-get update && apt-get install gnupg curl -y && \
    curl https://linux-clients.seafile.com/seafile.asc -o /usr/share/keyrings/seafile-keyring.asc && \
    echo deb [arch=amd64 signed-by=/usr/share/keyrings/seafile-keyring.asc] https://linux-clients.seafile.com/seafile-deb/bullseye/ stable main | tee /etc/apt/sources.list.d/seafile.list && \
    apt-get update -y && \
    apt-get install -y seafile-cli procps grep vim jq && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

RUN mkdir -p ${SEAFILE_HOME}

WORKDIR ${SEAFILE_HOME}

COPY start.sh ${SEAFILE_HOME}/start.sh

RUN chmod +x ${SEAFILE_HOME}/start.sh && \
    useradd -U -d ${SEAFILE_HOME} -s /bin/bash seafile && \
    usermod -G users seafile && \
    chown seafile:seafile -R ${SEAFILE_HOME} && \
    su - seafile -c "seaf-cli init -c ${SEAFILE_HOME}/.ccnet -d ${SEAFILE_HOME}"

CMD ["./start.sh"]
