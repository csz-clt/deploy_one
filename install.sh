#!/bin/sh

#install docker and docker-compose
sh docker/install-docker.sh
#users
COLORLIGHT_USER=colorlight
COLORLIGHT_USER_UID=3991
COLORLIGHT_GROUP=colorlight
COLORLIGHT_GROUP_GID=3991
MYSQL_USER=mysql
NGINX_USER=www-data

CURR_PATH=$(pwd)/clt_deploy
TEMPLATE_DIR=template

checkUsers()
{
    egrep "$COLORLIGHT_GROUP" /etc/group >& /dev/null
    if [ $? -ne 0 ]
    then
        groupadd $COLORLIGHT_GROUP -g $COLORLIGHT_GROUP_GID
    fi

    egrep "$COLORLIGHT_USER" /etc/passwd >& /dev/null
    if [ $? -ne 0 ]
    then
        useradd $COLORLIGHT_USER -g $COLORLIGHT_GROUP -u $COLORLIGHT_USER_UID -m -s /sbin/nologin
    fi

    egrep "$MYSQL_USER" /etc/passwd >& /dev/null
    if [ $? -ne 0 ]
    then
        useradd $MYSQL_USER -g $COLORLIGHT_GROUP -m -s /sbin/nologin
    fi

    egrep "NGINX_USER" /etc/passwd >& /dev/null
    if [ $? -ne 0 ]
    then
        useradd NGINX_USER -g $COLORLIGHT_GROUP -m -s /sbin/nologin
    fi
}
check_and_install_docker()
{
    docker -v
    if [ $? -eq 0 ];then
        docker_status=`service docker status | grep Active | awk '{print $2}'`
        if [ $docker_status != "active" ]; then
            systemctl start docker
            echo "restart docker service"
        fi
        echo "docker service already exists."
    else
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        if [ $? -eq 0 ];then
            echo "docker-ce install success."
        else
            echo "install docker fail from https://get.docker.com, check your network."
            exit 1
        fi
    fi
}
check_and_install_docker_compose()
{
    docker-compose -v > /dev/null 2>&1
    if [ $? -ne 0 ];then
      #docker_compose install
      sudo curl -L --fail https://github.com/docker/compose/releases/download/1.27.4/run.sh -o /usr/local/bin/docker-compose  > /dev/null 2>&1
      sudo chmod +x /usr/local/bin/docker-compose
    fi


    docker-compose -v > /dev/null 2>&1
    if [ $? -eq 0 ];then
        echo "docker-compose install success."
    else
        echo "install docker-compose fail from https://github.com/docker/compose/releases/download/1.26.0/run.sh, check your network."
        exit 1
    fi
}
read_configuration()
{
    _address=`cat config | grep _address | awk -F= '{print $2}' | sed -e 's/http:\/\///g' -e 's/https:\/\///g'`
    _port=`cat config | grep -m 1 _port | awk -F= '{print $2}'`
    _open_ssl=`cat config | grep _open_ssl | awk -F= '{print $2}'`
    _port_websocket=`cat config | grep _port_websocket | awk -F= '{print $2}'`


    if [ -z $_address ]; then
        _address=`curl -s --connect-timeout 10 -m 20 curl http://members.3322.org/dyndns/getip`
        if [ $? -ne 0 ]; then
            echo "please set your [ip/address] in configuration file:${CURR_PATH}/config"
            exit 1
        fi
    fi

    if [ $_open_ssl = 'true' ];then
        sed -e "s|listen 9999;|listen ${_port_websocket};|g" -e "s|AAAA|${_address}|g" ${CURR_PATH}/template/ssl_myconf.conf.template > ${CURR_PATH}/nginx/myconf.conf
        sed -e "s|server-url: AAAA|server_url: https://${_address}|g" -e "s|corPort: 8888|corPort: 443|g" ${CURR_PATH}/template/application.yml.template > ${CURR_PATH}/app/application.yml
    else
        sed -e "s|listen 8888;|listen ${_port};|g" -e "s|server_name AAAA;|server_name ${_address};|g" ${CURR_PATH}/template/myconf.conf.template > ${CURR_PATH}/nginx/myconf.conf
        sed -e "s|server-url: AAAA|server_url: http://${_address}|g" -e "s|corPort: 8888|corPort: ${_port}|g" ${CURR_PATH}/template/application.yml.template > ${CURR_PATH}/app/application.yml
    fi
}

update_images_version()
{
    _one_app_tag=`cat config | grep -m 1 _one_app | awk -F= '{print $2}'`
    _one_nginx_tag=`cat config | grep -m 1 _one_nginx | awk -F= '{print $2}'`
    _one_redis_tag=`cat config | grep -m 1 _one_redis | awk -F= '{print $2}'`
    _one_ws_tag=`cat config | grep -m 1 _one_ws | awk -F= '{print $2}'`
    _one_mysql_tag=`cat config | grep -m 1 _one_mysql | awk -F= '{print $2}'`

    _port=`cat config | grep -m 1 _port | awk -F= '{print $2}'`
    _port_websocket=`cat config | grep _port_websocket | awk -F= '{print $2}'`

    sed -e "s| colorlightwzg/one-mysql:TAG| colorlightwzg/one-mysql:${_one_mysql_tag}| g" \
        -e "s| colorlightwzg/one-app:TAG| colorlightwzg/one-app:${_one_app_tag}| g" \
        -e "s| colorlightwzg/one-nginx:TAG| colorlightwzg/one-nginx:${_one_nginx_tag}| g" \
        -e "s| colorlightwzg/one-ws:TAG| colorlightwzg/one-ws:${_one_ws_tag}| g" \
        -e "s| colorlightwzg/one-redis:TAG| colorlightwzg/one-redis:${_one_redis_tag}| g" \
        -e "s| - PORT_80:80| - ${_port}:80| g" \
        -e "s| - PORT_WS:8443| - ${_port_websocket}:8443| g" \
        ${CURR_PATH}/template/docker-compose.yml.template > ${CURR_PATH}/docker-compose.yml
}

makeDir() {
  mkdir -p $CURR_PATH && chown ${COLORLIGHT_USER}:${COLORLIGHT_GROUP} $CURR_PATH
  echo "正在初始化colorlight cloud部署目录:$(realpath $CURR_PATH)..."
  cp -r ${TEMPLATE_DIR}/mysql $CURR_PATH && chown ${MYSQL_USER}:${COLORLIGHT_GROUP} ${TEMPLATE_DIR}/mysql
  cp -r ${TEMPLATE_DIR}/nginx $CURR_PATH && chown ${NGINX_USER}:${COLORLIGHT_GROUP} ${TEMPLATE_DIR}/nginx
  cp -r ${TEMPLATE_DIR}/redis $CURR_PATH && chown ${COLORLIGHT_USER}:${COLORLIGHT_GROUP} ${TEMPLATE_DIR}/redis
  cp -r ${TEMPLATE_DIR}/ws $CURR_PATH && chown ${COLORLIGHT_USER}:${COLORLIGHT_GROUP} ${TEMPLATE_DIR}/redis
}

check_and_install_docker && check_and_install_docker_compose

checkUsers
makeDir
#read and set configuration
read_configuration
#read and reset docker images version
update_images_version
#restart docker-compose
docker-compose down && docker-compose up -d
echo "SUCCESS:colorlight cloud部署完成"
