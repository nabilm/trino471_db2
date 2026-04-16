ARG BASE=trinodb/trino:480
FROM $BASE
COPY --chown=trino:trino target/trino-db2-480/* /usr/lib/trino/plugin/db2/
# Remove Security Manager flag — unsupported in JDK 25 (shipped with Trino 480)
RUN sed -i '/-Djava.security.manager/d' /etc/trino/jvm.config
