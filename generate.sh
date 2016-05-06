#!/bin/bash
set -e

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

ppas=(
	[54]='php5-oldstable'
	[55]='php5'
	[56]='php5-5.6'
	[70]='php'
)

# Set default timezone
TZ='Europe/Vienna'

# Building php-fpm images
for version in "${versions[@]}"; do
	versionShort=`echo $version | tr -d '.'`
	majorVersion=`echo $version | sed 's/^\([[:digit:]]*\).*$/\1/'`

	directory="${version}/fpm"
	file="${directory}/Dockerfile"

	echo "Generating ${file}"

	ppa=${ppas[$versionShort]}
	package="php${majorVersion}-fpm"
	binary="php${majorVersion}-fpm"
	config="/etc/php${majorVersion}/fpm/php-fpm.conf"
	extensions="php5-sqlite php5-pgsql php5-mysqlnd php5-mcrypt php5-intl php5-gd php5-curl php5-xsl"
	cliBinary="php${majorVersion}"

	if [[ ${version} == "5.4" ]]; then
		package+=" php5-cli"
	fi

	if [[ ${majorVersion} == "7" ]]; then
		package="php7.0-fpm"
		binary="php-fpm7.0"
		config='/etc/php/7.0/fpm/php-fpm.conf'
		extensions="php7.0-sqlite php7.0-pgsql php7.0-mysql php7.0-mcrypt php7.0-intl php7.0-gd php7.0-curl php7.0-xml php7.0-mbstring"
		cliBinary="php"
	fi

	cat <<- DOCKERFILE > ${file}
		# Beware: This file is generated by the generate.sh script!
		FROM ubuntu:14.04
		MAINTAINER Martin Prebio <mp@25th-floor.com>
		EXPOSE 9000

		ENV DEBIAN_FRONTEND noninteractive
                ENV TZ=${TZ}

                RUN ln -snf /usr/share/zoneinfo/\$TZ /etc/localtime \\
			&& echo \$TZ > /etc/timezone \\
			&& dpkg-reconfigure -f noninteractive tzdata

		RUN apt-get update \\
			&& apt-get dist-upgrade -y \\
			&& apt-get install -y software-properties-common language-pack-en-base git \\
			&& LC_ALL=en_US.UTF-8 add-apt-repository ppa:ondrej/${ppa} \\
			&& apt-get update \\
			&& apt-get install -y ${package} ${extensions} \\
			&& apt-get clean \\
			&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \\
			&& ${cliBinary} -r 'readfile("https://getcomposer.org/installer");' > composer-setup.php \\
			&& ${cliBinary} composer-setup.php --install-dir=/usr/local/bin --filename=composer \\
			&& rm composer-setup.php

		# Prepare run directory\nRUN mkdir /run/php\n\nWORKDIR /var/www\n\n" >> ${file}
		COPY php-fpm.conf ${config}
		CMD ["${binary}"]
	DOCKERFILE

        # do some code-styling for Dockerfile readability
        sed -i '' -e "s|^&&|$(printf '\t')\&\&|g" ${file}

	cp php-fpm.conf ${directory}

	docker build -f ${file} --tag "twentyfifth/php-fpm:${version}" ${directory}/
done

# Building php-nginx images
for version in "${versions[@]}"; do
	majorVersion=`echo $version | sed 's/^\([[:digit:]]*\).*$/\1/'`

	directory="${version}/nginx"
	file="${directory}/Dockerfile"
	supervisor="${directory}/supervisord.conf"

	echo "Generating ${file}"

	binary="php${majorVersion}-fpm"
	if [[ ${majorVersion} == "7" ]]; then
		binary="php-fpm7.0"
	fi

	cat <<- DOCKERFILE > ${file}
		# Beware: This file is generated by the generate.sh script!
		FROM twentyfifth/php-fpm:${version}
		MAINTAINER Martin Prebio <mp@25th-floor.com>
		EXPOSE 80

		ENV TZ=${TZ}

		RUN ln -snf /usr/share/zoneinfo/\$TZ /etc/localtime \\
			&& echo \$TZ > /etc/timezone \\
			&& dpkg-reconfigure -f noninteractive tzdata

		RUN add-apt-repository ppa:nginx/development \\
			&& apt-get update \\
			&& apt-get install -y supervisor nginx \\
			&& apt-get clean \\
			&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \\
			&& ln -sf /dev/stdout /var/log/nginx/access.log \\
			&& ln -sf /dev/stderr /var/log/nginx/error.log

		COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
		COPY nginx-site.conf /etc/nginx/sites-enabled/default

		CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
	DOCKERFILE

        # do some code-styling for Dockerfile readability
        sed -i '' -e "s|^&&|$(printf '\t')\&\&|g" ${file}

	cat <<- SUPERVISOR > ${supervisor}
		[supervisord]
		nodaemon=true
		loglevel=debug
		logfile=/proc/self/fd/2
		logfile_maxbytes=0
		
		[program:php-fpm]
		command=${binary}
		autostart=true
		autorestart=true
		redirect_stderr=true
		stdout_logfile=/proc/self/fd/2
		stdout_logfile_maxbytes=0
		stderr_logfile=/proc/self/fd/2
		stderr_logfile_maxbytes=0

		[program:nginx]
		command=nginx -g "daemon off;"
		autostart=true
		autorestart=true
		redirect_stderr=true
		stdout_logfile=/proc/self/fd/2
		stdout_logfile_maxbytes=0
		stderr_logfile=/proc/self/fd/2
		stderr_logfile_maxbytes=0
	SUPERVISOR

	cp nginx-site.conf ${directory}

	docker build -f ${file} --tag "twentyfifth/php-nginx:${version}" ${directory}/
done
