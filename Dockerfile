
# Create global variables. By creating them here they can be reached throughout the whole dockerfile
# global args
ARG FLEDGE_DISTRIBUTION
ARG FLEDGE_PLATFORM
ARG OS_CODENAME


##### AMD64 section ##### 
FROM --platform=linux/amd64 ubuntu:focal-20231003 AS stage-amd64
ARG FLEDGE_DISTRIBUTION=ubuntu2004
ARG FLEDGE_PLATFORM=x86_64
ARG SNAP7_PLATFORM=x86_64
ARG OS_CODENAME=focal


##### ARM/v7 section ##### 
FROM --platform=linux/arm/v7 debian:bullseye-20231009-slim as stage-arm
ARG FLEDGE_DISTRIBUTION=bullseye
ARG FLEDGE_PLATFORM=armv7l
ARG OS_CODENAME=bullseye


##### Final arm/amd section ##### 
# pick the right base image created before based on architecture (automatically set by docker depending on chosen architecture)
ARG TARGETARCH
# Select final stage based on TARGETARCH ARG
FROM stage-${TARGETARCH} as base

##### Build arguments & Settings #####
# Collect & pickup the args from previous stages
# the ones without a definition are pre-defined in the stages before.
ARG FLEDGE_DISTRIBUTION
ARG FLEDGE_PLATFORM
ENV FLEDGE_VERSION=3.0.0
ARG POSTGRES_VERSION=13
ARG OS_CODENAME

# Locations for fledge and Postres.

ARG FLEDGE_ROOT_DIR=/usr/local/fledge
ARG FLEDGE_DATA_DIR=/usr/local/fledge/data
ARG POSTGRES_DATA_DIR=${FLEDGE_DATA_DIR}/postgresql

# Avoid interactive questions when installing Kerberos
ENV DEBIAN_FRONTEND=noninteractive

# Generic commands
# These commands are used throughout the Dockerfile
# NB: the combined commands need to be executed as a shell -c!
# otherwise the commands are not tied together properly
ARG APT_UPDATE="apt-get update --no-install-recommends"
ARG APT_CERTS="apt-get install -y --no-install-recommends --reinstall ca-certificates"
ARG APT_UPGRADE=" apt-get upgrade -y --no-install-recommends"
ARG APT_START=${APT_UPDATE}" && "${APT_CERTS}" && "${APT_UPGRADE}
ARG APT_INSTALL="apt install -y --no-install-recommends"
ARG APT_END="apt autoremove -y && apt clean -y && rm -rf /var/lib/apt/lists/"

# timezone, fledge needs it
ENV TZ=UTC

# Set Locales
# https://serverfault.com/questions/54591/how-to-install-change-locale-on-debian
RUN /bin/bash -c "${APT_START}" && \
	${APT_INSTALL} \
	#Install locales package
	locales && \
	# set timezone
	ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
	# Uncomment en_US.UTF-8 for inclusion in generation
	sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && \
	# Generate locale
	locale-gen && \
	# General cleanup after using apt
	/bin/bash -c "${APT_END}"
	## Export env vars
	# these are not picked up by the scripts
ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8


################ Prepare needed users  ###############
RUN groupadd -g 105 postgres && \
	groupadd -g 104 ssl-cert && \
	useradd -u 103 -g postgres -G ssl-cert -s /bin/bash -d /var/lib/postgresql postgres


################ Setup container with needed/convenient packages  ###############
 # Update & upgrade the Docker container
 
RUN /bin/bash -c "${APT_START}" && \
	${APT_INSTALL} \
 # Install apt packages
	git \
	iputils-ping \
	inetutils-telnet \
	nano \
	rsyslog \
	sed \
	wget \
	procps \
	sysstat \
	jq \
	dos2unix \
	logrotate \
	build-essential \
	zlib1g-dev \
	libssl-dev \
	libsasl2-dev \
	libzstd-dev \
	libcurl4-openssl-dev \
	openssh-client \
	&& \

	# Fake service control as docker container doesn't use it
	printf '#!/bin/bash \nexit 0' > /usr/bin/systemctl && \
	chmod 755 /usr/bin/systemctl && \
	# General cleanup after using apt
	/bin/bash -c "${APT_END}"

########### Install Fledge plugins from DEB by Dianomic ##############
# these env. variables somehow are not pushed properly in the last step.

ENV FLEDGE_ROOT=${FLEDGE_ROOT_DIR}
ENV FLEDGE_DATA=${FLEDGE_DATA_DIR}
ENV PATH="${FLEDGE_ROOT}/bin:${PATH}"
ENV LD_LIBRARY_PATH="${FLEDGE_ROOT}/lib:$LD_LIBRARY_PATH"

	# install plugins from deb package
    # the package is now pre-loaded on top of this file
	# start with apt update, we ditched all info in last stage to save space
RUN /bin/bash -c "${APT_START}" && \
	${APT_INSTALL} gnupg && \
	# Get the deb package from dianomic
	wget -q -O - http://archives.fledge-iot.org/KEY.gpg | apt-key add - && \

	echo "deb http://archives.fledge-iot.org/${FLEDGE_VERSION}/${FLEDGE_DISTRIBUTION}/${FLEDGE_PLATFORM}/ / " | tee -a /etc/apt/sources.list && \
	# and do the actual update
	/bin/bash -c "${APT_UPDATE}" && \

	${APT_INSTALL} \
	# install from repository
	# automake & python3-dev apparently needed for install of some pyjq package
	automake \ 
	python3-dev \
	fledge \
	
	fledge-filter-delta  \
	fledge-filter-asset  \ 
	fledge-filter-change  \
	fledge-filter-metadata  \
	fledge-filter-python35  \
	fledge-filter-rate   \
	fledge-filter-threshold   \
	fledge-filter-omfhint  \

	## North
	fledge-north-httpc  \
	fledge-north-http-north   \

	## South
	fledge-south-modbustcp   \
	fledge-south-sinusoid  \
	fledge-south-http-south  \
	fledge-south-modbus   \
	fledge-south-mqtt-readings  \
	fledge-south-s2opcua \
	# continue after install
	&& \

	# make sure to always keep the package, do not upgrade -> will go wrong anyway..
	apt-mark hold fledge && \

	# Cleanup fledge installation packages
	rm -f /*.tgz && \ 
	# You may choose to leave the installation packages in the directory in case you need to troubleshoot
	rm -rf -r /fledge && \

	# General cleanup after using apt
	/bin/bash -c "${APT_END}"



########### Install & Configure Postgres ##############
# this is done once -> its preconfig values are kept in the layer
# so when the container is mounted these settings are written into the volume.
# NB: when a container already exists, these settings are NOT updated.
ENV POSTGRES_DATA=${POSTGRES_DATA_DIR}

RUN /bin/bash -c "${APT_START}" && \
	
	# Create the repository configuration:
	# Postgres 13 is not always included, so we add the repo
	echo "deb http://apt.postgresql.org/pub/repos/apt ${OS_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \

	# Import the repository signing key:
	wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
	${APT_UPDATE} && \
	
	# Install the latest version of PostgreSQL.
	# If you want a specific version, use 'postgresql-13' or similar instead of 'postgresql':
	${APT_INSTALL} \
	postgresql-${POSTGRES_VERSION} sudo rsync && \
	
	# Create Postgres data dir, it's a subdir of the fledge data location.
	# it was not possible to change fledge data location..
	mkdir -p ${POSTGRES_DATA} && \
	chown postgres:postgres ${POSTGRES_DATA} && \
	rsync -av /var/lib/postgresql/ ${POSTGRES_DATA} && \
	rm -rf /var/lib/postgresql/ && \

	# Postgres settings. Remote login & data store location
	sed -i "/data_directory /c\data_directory =  '${POSTGRES_DATA}/${POSTGRES_VERSION}/main' " /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf && \
	sed -i "/#listen_addresses/c\listen_addresses='*'" /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf && \
	sed -i "s|all             all             127.0.0.1/32|all             all             0.0.0.0/0|g" /etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf && \
	sed -i "s|all             all             ::1/128|all             all             ::/0|g" /etc/postgresql/${POSTGRES_VERSION}/main/pg_hba.conf && \
	#limit resources
	sed -i "/#shared_buffers/c\shared_buffers = 64MB" /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf && \
	sed -i "/#temp_buffers/c\temp_buffers = 4MB" /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf && \
	sed -i "/#work_mem/c\work_mem = 2MB" /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf && \
	sed -i "/#maintenance_work_mem/c\maintenance_work_mem = 16MB" /etc/postgresql/${POSTGRES_VERSION}/main/postgresql.conf && \
	
	# create user
	service postgresql start && \
	sudo -u postgres createuser -d root && \
	sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'berry'" && \
	service postgresql stop && \
	
    # General cleanup after using apt
	/bin/bash -c "${APT_END}"
	
# Postgres port
EXPOSE 5432

################# Configure Fledge ###############
WORKDIR /
# Fledge API port for FELDGE API over HTTP
EXPOSE 8081
# Load the needed sources
# unfortunately had to add dos2unix for line endings crapped up by windows every time file is edited
# Disable apt-compat. we don't need it in a container
COPY /scripts/fledge.sh ${FLEDGE_ROOT}/fledge.sh
COPY /scripts/logrotate.conf /etc/logrotate.conf
RUN dos2unix ${FLEDGE_ROOT}/fledge.sh && \
    chmod +x ${FLEDGE_ROOT}/fledge.sh && \
    dos2unix /etc/logrotate.conf && \
    mv /etc/cron.daily/apt-compat /etc/cron.daily/apt-compat.disabled 

################# Start Fledge & other Services ###############

VOLUME ${FLEDGE_DATA_DIR}
VOLUME /var/log
# start rsyslog, FLEDGE, and tail syslog
# also removes remaining .pid files if needed
ENTRYPOINT /bin/bash -c "$FLEDGE_ROOT/fledge.sh"

