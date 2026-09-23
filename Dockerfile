FROM ubuntu:20.04 as builder

# This Docker image builds the dependencies for the Rapthor pipeline.
# It lives on the head of its dependencies.

# Install all build-time dependencies
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository -y ppa:ubuntu-toolchain-r/test && \
    apt-get update && \
    apt-get install -y \
        bison \
        build-essential \
        casacore-data \
        casacore-dev \
        cmake \
        flex \
        gfortran \
        git \
        libblas-dev \
        libcfitsio-dev \
        libfftw3-dev \
        libgsl-dev \
        libgtkmm-3.0-dev \
        libhdf5-serial-dev \
        liblapack-dev \
        liblua5.3-dev \
        libncurses5-dev \
        libpng-dev \
        libpython3-dev \
        pkg-config \
        python3 \
        python3-casacore \
        python3-numpy \
        wcslib-dev \
        wget && \
    mkdir -p /src

# Boost manuell auf Version 1.77.0 upgraden (wird für schaapcommon/wsclean benötigt)
RUN cd /src && \
    wget -O boost_1_77_0.tar.bz2 https://sourceforge.net/projects/boost/files/boost/1.77.0/boost_1_77_0.tar.bz2/download && \
    tar -xf boost_1_77_0.tar.bz2 && \
    cd boost_1_77_0 && \
    ./bootstrap.sh --prefix=/usr/local --with-python=python3 && \
    ./b2 install -j`nproc` && \
    cd .. && rm -rf boost_1_77_0*

WORKDIR /src

# Build portable binaries by default
ARG PORTABLE=TRUE

ARG LOFARSTMAN_VERSION=master
RUN git clone --depth 1 --branch main \
        https://github.com/lofar-astron/LofarStMan && \
    mkdir LofarStMan/build && \
    cd LofarStMan/build && \
    cmake .. -DPORTABLE=${PORTABLE} && \
    make install -j`nproc`

ARG DYSCO_VERSION=master
RUN git clone --depth 1 --branch ${DYSCO_VERSION} \
        https://github.com/aroffringa/dysco.git && \
    mkdir dysco/build && \
    cd dysco/build && \
    cmake .. -DPORTABLE=${PORTABLE} && \
    make install -j`nproc`

ARG IDG_VERSION=master
# IDG benötigt ein neueres CMake
RUN apt-get update && apt-get install -y wget && \
    wget -qO- https://cmake.org/files/v3.26/cmake-3.26.4-linux-x86_64.tar.gz | tar --strip-components=1 -xz -C /usr/local && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://git.astron.nl/RD/idg.git && \
    mkdir idg/build && \
    cd idg/build && \
    cmake .. && \
    make install -j`nproc`

ARG AOFLAGGER_VERSION=master
RUN git clone --branch ${AOFLAGGER_VERSION} \
        https://gitlab.com/aroffringa/aoflagger.git && \
    mkdir aoflagger/build && \
    cd aoflagger && git fetch && git checkout bfb3978e734911457555ac244d255f4b4ce6df68 && \
    cd build && \
    cmake .. -DPORTABLE=${PORTABLE} && \
    make install -j`nproc`

ARG LOFARBEAM_VERSION=master
RUN git clone  --depth 1 --branch ${LOFARBEAM_VERSION} \
        https://github.com/lofar-astron/LOFARBeam.git && \
    mkdir LOFARBeam/build && \
    cd LOFARBeam/build && \
    cmake .. && \
    make install -j`nproc`

ARG EVERYBEAM_VERSION=v0.3.1
RUN git clone --depth 1  --branch ${EVERYBEAM_VERSION} \
        https://git.astron.nl/RD/EveryBeam.git && \
    mkdir EveryBeam/build && \
    cd EveryBeam/build && \
    cmake .. && \
    make install -j`nproc`

ARG SAGECAL_VERSION=master
RUN git clone --depth 1 --branch ${SAGECAL_VERSION} \
        https://github.com/nlesc-dirac/sagecal && \
    mkdir sagecal/build && \
    cd sagecal/build && \
    cmake .. -DLIB_ONLY=1 && \
    make install -j`nproc`

ARG DP3_VERSION=v5.3
RUN git clone --branch ${DP3_VERSION} \
        https://git.astron.nl/RD/DP3.git && \
    mkdir DP3/build && \
    cd DP3/build && \
    cmake .. -DPORTABLE=${PORTABLE} -DLIBDIRAC_PREFIX=/usr/local/ && \
    make install -j`nproc`

ARG WSCLEAN_VERSION=master
RUN git clone --depth 1 --branch ${WSCLEAN_VERSION} \
        https://gitlab.com/aroffringa/wsclean.git && \
    mkdir wsclean/build && \
    cd wsclean/build && \
    cmake .. -DPORTABLE=${PORTABLE} && \
    make install -j`nproc`

# Pip von PyPA holen
RUN wget https://bootstrap.pypa.io/get-pip.py && \
    python3 get-pip.py

# Python-Standard-Build-Tools installieren
RUN python3 -m pip install --no-cache-dir --upgrade \
    cwl-runner \
    cwltool

# AO tools
RUN cd /src && \
    git clone https://github.com/aroffringa/modeltools.git modeltools && \
    cd modeltools && \
    mkdir build && \
    cd build && \
    cmake -DPORTABLE=True ../ && \
    make -j4 && \
    cp bbs2model cluster editmodel render /usr/local/bin/ && \
    cd

# Tom's stuff
ADD makemask /src/makemask
RUN cd /src/makemask && \
    gcc makeMaskFits.c -o makeMaskFits -lcfitsio -lm && \
    gcc makeNoiseMapFits.c -o makeNoiseMapFits -lcfitsio -lm && \
    gcc makeNoiseMapFitsLow.c -o makeNoiseMapFitsLow -lcfitsio -lm && \
    gcc makeCombMaskFits.c -o makeCombMaskFits -lcfitsio -lm && \
    cp makeMaskFits makeNoiseMapFits makeCombMaskFits makeNoiseMapFitsLow /usr/local/bin/ && \
    cd

#---------------------------------------------------------------------------
# Runner Stage
#---------------------------------------------------------------------------
FROM ubuntu:20.04 as runner
RUN mkdir /src
COPY --from=builder /usr/local /usr/local
RUN chmod +rx /usr/local/bin/*

SHELL ["/bin/bash", "-c"]

ARG LOFARSTMAN_VERSION=master
ARG DYSCO_VERSION=master
ARG IDG_VERSION=master
ARG AOFLAGGER_VERSION=master
ARG LOFARBEAM_VERSION=master
ARG EVERYBEAM_VERSION=master
ARG DP3_VERSION=master
ARG WSCLEAN_VERSION=master

# Laufzeitabhängigkeiten installieren (Alte Boost-Pakete entfernt, da wir /usr/local nutzen)
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        casacore-tools \
        libatkmm-1.6-1v5 \
        libcairomm-1.0-1v5 \
        libcasa-casa4 \
        libcasa-fits4 \
        libcasa-measures4 \
        libcasa-ms4 \
        libcasa-python3-4 \
        libcasa-scimath4 \
        libcasa-tables4 \
        libcfitsio8 \
        libfftw3-double3 \
        libfftw3-single3 \
        libglibmm-2.4-1v5 \
        libgomp1 \
        libgsl23 \
        libgtkmm-3.0-1v5 \
        libhdf5-103 \
        libhdf5-cpp-103 \
        liblapack3 \
        liblua5.3-0 \
        libpangomm-1.4-1v5 \
        libpng16-16 \
        libpython3.8 \
        libsigc++-2.0-0v5 \
        libstdc++6 \
        nodejs \
        python3 \
        python3-casacore \
        python3-distutils \
        tmux \
        wget \
        git && \
    rm -rf /var/lib/apt/lists/*

# Wichtig: Den Linker anweisen, die neuen Boost-Bibliotheken in /usr/local/lib zu indizieren
RUN ldconfig

# Install WSRT Measures (extra casacore data)
RUN wget -q -O /WSRT_Measures.ztar \
        ftp://ftp.astron.nl/outgoing/Measures/WSRT_Measures.ztar && \
    cd /var/lib/casacore/data && \
    tar xfz /WSRT_Measures.ztar && \
    rm /WSRT_Measures.ztar

# Python PIP Pakete installieren
RUN python3 -m pip install h5py pandas pyyaml astropy matplotlib==3.5.2 scipy shapely bdsf ipython radio_beam scikit-learn
