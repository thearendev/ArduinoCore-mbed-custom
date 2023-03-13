FROM ubuntu:focal
ENV TZ=Europe/Rome
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt-get update \
  && apt-get -y install build-essential curl gcc-arm-none-eabi git jq mercurial python3.9-dev python3.9-full rsync \
  && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/bin/python3.9 /usr/bin/python \
  && curl -sSL https://bootstrap.pypa.io/get-pip.py | python
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH="$PATH:/usr/local/cargo/bin"
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
RUN pip install mbed-cli
RUN mkdir /ace /patches /dist
VOLUME [ "/patches" ]
VOLUME [ "/dist" ]
WORKDIR /ace
COPY docker/build.sh /
RUN chmod 755 /build.sh
CMD [ "/build.sh" ]
