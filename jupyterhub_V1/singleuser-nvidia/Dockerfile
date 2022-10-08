FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

LABEL maintainer="Bayes Cluster Maintenance Group <"
ARG NB_USER="bayes"
ARG NB_UID="1000"
ARG NB_GID="100"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install all OS dependencies for fully functional notebook server
USER root
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update --yes && \
    apt-get upgrade --yes && \
    apt-get install --yes --no-install-recommends \
    bzip2 \
    ca-certificates \
    fonts-liberation \
    locales \
    pandoc \
    run-one \
    sudo \
    tini \
    wget \
    curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

RUN adduser --disabled-password \
    --gecos "Default user" \
    --uid ${NB_UID} \
    ${NB_USER}

# Configure environment
ENV CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    NB_USER="${NB_USER}" \
    NB_UID=${NB_UID} \
    NB_GID=${NB_GID} \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" \
    HOME="/home/${NB_USER}"

COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

RUN mkdir "/home/${NB_USER}/work" && \
    fix-permissions "/home/${NB_USER}"
RUN fix-permissions "/home/${NB_USER}"

# Install miniconda 
ENV CONDA_URL="https://mirrors.bfsu.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
RUN curl -LO ${CONDA_URL} 
RUN bash Miniconda3-latest-Linux-x86_64.sh -p ${CONDA_DIR} -b
RUN rm -rf Miniconda3-latest-Linux-x86_64.sh
RUN conda config --system --prepend channels conda-forge
RUN chown ${NB_UID}:${NB_GID} ${CONDA_DIR}
RUN conda init
COPY condarc /home/${NB_USER}/.condarc
RUN conda install -c anaconda jupyter
RUN conda install -c conda-forge jupyterlab
RUN conda install -c conda-forge jupyterhub
RUN conda config --system --prepend envs_dirs '/home/${NB_USER}/.conda/envs'
EXPOSE 8888
ENTRYPOINT ["tini", "--"]
CMD ["jupyter", "lab"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
# Currently need to have both jupyter_notebook_config and jupyter_server_config to support classic and lab
COPY jupyter_server_config.py /etc/jupyter/

# Fix permissions on /etc/jupyter as root
USER root

# Legacy for Jupyter Notebook Server, see: [#1205](https://github.com/jupyter/docker-stacks/issues/1205)
RUN sed -re "s/c.ServerApp/c.NotebookApp/g" \
    /etc/jupyter/jupyter_server_config.py > /etc/jupyter/jupyter_notebook_config.py && \
    fix-permissions /etc/jupyter/

# HEALTHCHECK documentation: https://docs.docker.com/engine/reference/builder/#healthcheck
# This healtcheck works well for `lab`, `notebook`, `nbclassic`, `server` and `retro` jupyter commands
# https://github.com/jupyter/docker-stacks/issues/915#issuecomment-1068528799
HEALTHCHECK  --interval=15s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -O- --no-verbose --tries=1 --no-check-certificate \
    http${GEN_CERT:+s}://localhost:8888${JUPYTERHUB_SERVICE_PREFIX:-/}api || exit 1

# Switch back to jovyan to avoid accidental container runs as root
USER ${NB_UID}

WORKDIR "${HOME}"