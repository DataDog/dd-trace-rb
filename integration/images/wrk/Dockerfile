FROM debian:jessie

RUN echo "===> Installing  tools..."  && \
    apt-get -y update && \
    apt-get -y install build-essential curl && \
    \
    echo "===> Installing wrk" && \
    WRK_VERSION=$(curl -L https://github.com/wg/wrk/raw/master/CHANGES 2>/dev/null | \
                  egrep '^wrk' | head -n 1 | awk '{print $2}') && \
    echo $WRK_VERSION  && \
    mkdir /opt/wrk && \
    cd /opt/wrk && \
    curl -L https://github.com/wg/wrk/archive/$WRK_VERSION.tar.gz | \
       tar zx --strip 1 && \
    make && \
    cp wrk /usr/local/bin/ && \
    \
    echo "===> Cleaning the system" && \
    apt-get -f -y --auto-remove remove build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /opt/wrk/

# Setup directory
RUN mkdir /scripts
RUN mkdir /data
WORKDIR /scripts

# Add scripts
COPY ./include /vendor/dd-demo
COPY ./wrk/scripts /scripts

# Set entrypoint
ENTRYPOINT ["./entrypoint.sh"]
