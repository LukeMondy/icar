FROM debian:stretch

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        file \
        g++ \
        gcc \
        gfortran \
        gfortran-6 \
        git \
        libfftw3-dev \
        m4 \
        make \
        wget \
        vim \
        zlib1g-dev \
        # end of list
    && apt-get clean autoclean \
    && apt-get autoremove --purge --yes \
    && rm -rf /var/lib/apt/lists/*

ARG REPO=https://github.com/LukeMondy/icar.git 

RUN git clone $REPO

WORKDIR icar

ENV TRAVIS_BUILD_DIR="/icar"
ENV WORKDIR="/tmp/"
ENV INSTALLDIR="/usr/"

RUN bash -c "source ci/icar_install_utils \
    && icar_before_install \
    && icar_install" \
    && rm -rf ${WORKDIR}

ENV FC=gfortran-6
ENV NETCDF=${INSTALLDIR}
ENV FFTW=/usr

RUN cd ${TRAVIS_BUILD_DIR} \
    && make -C src clean; \
       make -C src -j4 \
    && INSTALLDIR="${INSTALLDIR}/bin" make -C src install
