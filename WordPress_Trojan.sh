#!/bin/bash
# centos7/8 trojan WordPress一键安装脚本
# Author: hijk<https://hijk.art>


RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

CONFIG_FILE=/usr/local/etc/trojan/config.json

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        res=`which yum`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是CentOS"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        MAIN=${result%%.*}
        if [ $MAIN -lt 7 ]; then
            colorEcho $RED " 不受支持的CentOS版本"
            exit 1
         fi
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#             ${RED}CentOS 7/8 WordPress一键安装脚本${PLAIN}                #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

checkTrojan() {
    colorEcho $YELLOW " 该脚本仅适用于 https://hijk.art 网站的trojan一键脚本 安装wordpress用！"
    read -p " 退出请按n，按其他键继续：" answer
    [ "$answer" = "n" ] && exit 0

    if [ ! -f ${CONFIG_FILE} ]; then
        colorEcho $RED " 未安装trojan"
        exit 1
    fi
    DOMAIN=`grep -m1 cert $CONFIG_FILE | awk 'BEGIN { FS = "/" } ; { print $5 }'`
    if [ ! -f /etc/nginx/conf.d/${DOMAIN}.conf ]; then
        colorEcho $RED " 未找到域名的nginx配置文件"
        exit 1
    fi
    PORT=`grep local_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' '`
}

installPHP() {
    rpm -iUh https://rpms.remirepo.net/enterprise/remi-release-${MAIN}.rpm
    if [ $MAIN -eq 7 ]; then
	    sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi-php74.repo
    else
        sed -i '0,/enabled=0/{s/enabled=0/enabled=1/}' /etc/yum.repos.d/remi.repo
        dnf module install -y php:remi-7.4
    fi
    yum install -y php-cli php-fpm php-bcmath php-gd php-mbstring php-mysqlnd php-pdo php-opcache php-xml php-pecl-zip
    systemctl enable php-fpm.service
}

installMysql() {
    echo "# MariaDB 10.5 CentOS repository list
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.5/centos${MAIN}-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1" > /etc/yum.repos.d/mariadb.repo
    if [ $MAIN -eq 8 ]; then
        echo "module_hotfixes=1" >>  /etc/yum.repos.d/mariadb.repo
    fi

    yum remove -y MariaDB-server
    rm -rf /var/lib/mysql
    yum install -y MariaDB-server
    systemctl enable mariadb.service
}

installWordPress() {
    yum install -y wget
    mkdir -p /var/www;
    wget https://www.wordpress.org/latest.tar.gz
    if [ ! -f latest.tar.gz ]; then
    	colorEcho $RED " 下载WordPress失败，请稍后重试"
	    exit 1
    fi
    tar -zxf latest.tar.gz
    rm -rf /var/www/${DOMAIN}
    mv wordpress /var/www/${DOMAIN}
    rm -rf latest.tar.gz
}

config() {
    # config mariadb
    systemctl start mariadb
    DBNAME="wordpress"
    DBUSER="wordpress"
    DBPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1`
    mysql -uroot <<EOF
DELETE FROM mysql.user WHERE User='';
CREATE DATABASE $DBNAME default charset utf8mb4;
CREATE USER ${DBUSER}@'%' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON ${DBNAME}.* to ${DBUSER}@'%';
FLUSH PRIVILEGES;
EOF

    #config php
    sed -i 's/expose_php = On/expose_php = Off/' /etc/php.ini
    line=`cat -n /etc/php.ini | grep 'date.timezone' | tail -n1 | awk '{print $1}'`
    sed -i "${line}a date.timezone = Asia/Shanghai" /etc/php.ini
    sed -i 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=30/' /etc/php.d/10-opcache.ini
    if [ $MAIN -eq 7 ]; then
        sed -i 's/listen = 127.0.0.1:9000/listen = \/run\/php-fpm\/www.sock/' /etc/php-fpm.d/www.conf
    fi
    line=`cat -n /etc/php-fpm.d/www.conf | grep 'listen.mode' | tail -n1 | awk '{print $1}'`
    sed -i "${line}a listen.mode=0666" /etc/php-fpm.d/www.conf

    # config wordpress
    cd /var/www/$DOMAIN
    cp wp-config-sample.php wp-config.php
    sed -i "s/database_name_here/$DBNAME/g" wp-config.php
    sed -i "s/username_here/$DBUSER/g" wp-config.php
    sed -i "s/password_here/$DBPASS/g" wp-config.php
    sed -i "s/utf8/utf8mb4/g" wp-config.php
    #sed -i "1a \$_SERVER['HTTPS']='on';" index.php
    perl -i -pe'
  BEGIN {
    @chars = ("a" .. "z", "A" .. "Z", 0 .. 9);
    push @chars, split //, "!@#$%^&*()-_ []{}<>~\`+=,.;:/?|";
    sub salt { join "", map $chars[ rand @chars ], 1 .. 64 }
  }
  s/put your unique phrase here/salt()/ge
' wp-config.php
    #sed -i "23a define( 'WP_HOME', 'https://${DOMAIN}:${PORT}' );" wp-config.php
    #sed -i "24a define( 'WP_SITEURL', 'https://${DOMAIN}:${PORT}' );" wp-config.php

    chown -R apache:apache /var/www/$DOMAIN

    # config nginx
    cat > /etc/nginx/conf.d/${DOMAIN}.conf<<-EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name:${PORT}\$request_uri;
}
server {
    listen 8080;
    server_name ${DOMAIN};
    
    charset utf-8;
    
    set \$host_path "/var/www/${DOMAIN}";
    access_log  /var/log/nginx/${DOMAIN}.access.log  main buffer=32k flush=30s;
    error_log /var/log/nginx/${DOMAIN}.error.log;
    root   \$host_path;
    location / {
        index  index.php index.html;
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_index index.php;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        include fastcgi_params;
        fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
	    fastcgi_param  SERVER_PORT	${PORT};
	    fastcgi_param  HTTPS		"on";
    }
    location ~ \.(js|css|png|jpg|jpeg|gif|ico|swf|webp|pdf|txt|doc|docx|xls|xlsx|ppt|pptx|mov|fla|zip|rar)\$ {
        expires max;
        access_log off;
        try_files \$uri =404;
    }
}
EOF

    # config trojan
    sed -i -e "s/remote_addr\":\s*\".*\",/remote_addr\": \"127.0.0.1\",/" $CONFIG_FILE
    sed -i -e "s/remote_port\":\s*[0-9]*/remote_port\": 8080/" $CONFIG_FILE

    # restart service
    systemctl restart php-fpm mariadb nginx trojan
}

info() {
    colorEcho $BLUE " WordPress安装成功！"
    echo "==============================="
    echo -e "   ${BLUE}WordPress安装路径：${PLAIN}${RED}/var/www/${DOMAIN}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库：${PLAIN}${RED}${DBNAME}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库用户名：${PLAIN}${RED}${DBUSER}${PLAIN}"
    echo -e "   ${BLUE}WordPress数据库密码：${PLAIN}${RED}${DBPASS}${PLAIN}"
    echo -e "   ${BLUE}博客访问地址：${PLAIN}${RED}https://${DOMAIN}:${PORT}${PLAIN}"
    echo "==============================="
}

main() {
    slogon
    checkSystem
    checkTrojan
    installPHP
    installMysql
    installWordPress

    config

    info
}

main
