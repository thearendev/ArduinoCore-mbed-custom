# The pinned mbed-os tools (make.py / toolchains) use stdlib modules removed in
# Python 3.12+ (`imp`, `distutils`), so `mbed compile` fails on newer Python.
# Build on Python 3.9 (ubuntu:focal), matching the last known-good image.
FROM ubuntu:focal
ENV TZ=Europe/Rome
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt-get update \
  && apt-get -y install build-essential curl gcc-arm-none-eabi git jq mercurial python3.9-dev python3.9-full python3.9-venv rsync \
  && rm -rf /var/lib/apt/lists/*
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH="$PATH:/usr/local/cargo/bin"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
RUN python3.9 -m venv /venv
ENV PATH="/venv/bin:$PATH"
# Install wheel first (separate step) so mbed-cli's sdist builds its wheel;
# combining them can build mbed-cli before wheel is available -> pip exits 1.
RUN pip install -U pip setuptools wheel
RUN pip install mbed-cli
RUN mkdir /ace /patches /dist
VOLUME [ "/patches" ]
VOLUME [ "/dist" ]
WORKDIR /ace
COPY docker/build.sh /
RUN chmod 755 /build.sh
CMD [ "/build.sh" ]
