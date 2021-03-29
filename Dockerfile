ARG EXIST_VERSION=5.2.0

# START STAGE 1
FROM openjdk:8-jdk-slim as builder

USER root

ENV ANT_VERSION 1.10.9
ENV ANT_HOME /etc/ant-${ANT_VERSION}

WORKDIR /tmp

RUN apt-get update && apt-get install -y \
    wget \
    git

RUN wget http://www-us.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mkdir ant-${ANT_VERSION} \
    && tar -zxvf apache-ant-${ANT_VERSION}-bin.tar.gz \
    && mv apache-ant-${ANT_VERSION} ${ANT_HOME} \
    && rm apache-ant-${ANT_VERSION}-bin.tar.gz \
    && rm -rf ant-${ANT_VERSION} \
    && rm -rf ${ANT_HOME}/manual \
    && unset ANT_VERSION

ENV PATH ${PATH}:${ANT_HOME}/bin

FROM builder as tei

ARG PUBLISHER_LIB_VERSION=v2.8.11
ARG OAS_ROUTER_VERSION=v1.1.5
ARG PUBLISHER_VERSION=master
ARG SHAKESPEARE_VERSION=1.1.2
ARG VANGOGH_VERSION=1.0.6

# add key
RUN  mkdir -p ~/.ssh && ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# Build tei-publisher-lib
RUN  git clone https://github.com/eeditiones/tei-publisher-lib.git \
    && cd tei-publisher-lib \
    && git checkout ${PUBLISHER_LIB_VERSION} \
    && ant

RUN  git clone https://github.com/eeditiones/oas-router.git \
    && cd oas-router \
    && git checkout ${OAS_ROUTER_VERSION} \
    && ant

# Build shakespeare
RUN  git clone https://github.com/eeditiones/shakespeare.git \
    && cd shakespeare \
    && git checkout ${SHAKESPEARE_VERSION} \
    && ant

# Build vangogh
RUN  git clone https://github.com/eeditiones/vangogh.git \
    && cd vangogh \
    && git checkout ${VANGOGH_VERSION} \
    && ant

# Build tei-publisher-app
RUN  git clone https://github.com/eeditiones/tei-publisher-app.git \
    && cd tei-publisher-app \
    && echo Checking out ${PUBLISHER_VERSION} \
    && git checkout ${PUBLISHER_VERSION} \
    && ant

FROM existdb/existdb:${EXIST_VERSION}

COPY --from=tei /tmp/tei-publisher-lib/build/*.xar /exist/autodeploy
COPY --from=tei /tmp/oas-router/build/*.xar /exist/autodeploy
COPY --from=tei /tmp/tei-publisher-app/build/*.xar /exist/autodeploy
COPY --from=tei /tmp/shakespeare/build/*.xar /exist/autodeploy
COPY --from=tei /tmp/vangogh/build/*.xar /exist/autodeploy

ENV DATA_DIR /exist-data

ENV JAVA_TOOL_OPTIONS \
    -Dfile.encoding=UTF8 \
    -Dsun.jnu.encoding=UTF-8 \
    -Djava.awt.headless=true \
    -Dorg.exist.db-connection.cacheSize=${CACHE_MEM:-256}M \
    -Dorg.exist.db-connection.pool.max=${MAX_BROKER:-20} \
    -Dlog4j.configurationFile=/exist/etc/log4j2.xml \
    -Dexist.home=/exist \
    -Dexist.configurationFile=/exist/etc/conf.xml \
    -Djetty.home=/exist \
    -Dexist.jetty.config=/exist/etc/jetty/standard.enabled-jetty-configs \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+UseCGroupMemoryLimitForHeap \
    -XX:+UseG1GC \
    -XX:+UseStringDeduplication \
    -XX:MaxRAMFraction=1 \
    -XX:+ExitOnOutOfMemoryError \
    -Dorg.exist.db-connection.files=${DATA_DIR} \
    -Dorg.exist.db-connection.recovery.journal-dir=${DATA_DIR}

# pre-populate the database by launching it once
RUN [ "java", \
    "org.exist.start.Main", "client", "-l", \
    "--no-gui",  "--xpath", "system:get-version()" ]
