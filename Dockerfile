ARG BASE
FROM $BASE
COPY --chown=trino:trino target/trino-db2-471/* /usr/lib/trino/plugin/db2/
# Disable JIT to prevent SIGILL/SIGSEGV crashes under Rosetta x86 emulation on Apple Silicon
RUN echo "-Xint" >> /etc/trino/jvm.config
