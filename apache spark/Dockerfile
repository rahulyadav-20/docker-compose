FROM eclipse-temurin:11-jre

ARG SPARK_VERSION=3.5.0
ARG HADOOP_VERSION=3

ENV DEBIAN_FRONTEND=noninteractive \
    SPARK_HOME=/opt/spark \
    PATH=/opt/spark/bin:/opt/spark/sbin:$PATH \
    PYSPARK_PYTHON=python3 \
    SPARK_NO_DAEMONIZE=true

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      curl \
      ca-certificates \
      python3 \
      tini \
      procps \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz" \
    | tar -xz -C /opt \
    && ln -s "/opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}" /opt/spark

WORKDIR /opt/spark

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
