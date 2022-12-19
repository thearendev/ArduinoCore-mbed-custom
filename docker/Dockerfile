FROM ubuntu:22.10
RUN apt-get update \
  && apt-get -y install curl gcc-arm-none-eabi git jq mercurial python3 python3-pip rsync \
  && rm -rf /var/lib/apt/lists/*
RUN pip install mbed-cli
RUN pip install `curl -sSL https://github.com/ARMmbed/mbed-os/raw/latest/requirements.txt`
RUN mkdir /ace /patches /dist
VOLUME [ "/patches" ]
VOLUME [ "/dist" ]
WORKDIR /ace
COPY docker/build.sh /
RUN chmod 755 /build.sh
CMD [ "/build.sh" ]
