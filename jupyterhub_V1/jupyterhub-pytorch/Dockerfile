ARG SOURCE=ghcr.io
ARG BASE_CONTAINER=${SOURCE}/jupyter-base:0.0.3
FROM $BASE_CONTAINER

LABEL org.opencontainers.image.authors="Bayes Cluster Maintenance Group"
LABEL org.opencontainers.image.documentation="https://uicstat.com"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for fully functional notebook server
RUN apt-get update --yes && \
    apt-get install --yes --no-install-recommends \
    git \
    nano-tiny \
    tzdata \
    unzip \
    vim-tiny \
    openssh-client \
    less \
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    xclip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*