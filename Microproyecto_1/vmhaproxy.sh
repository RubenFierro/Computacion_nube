
#---------------------------APROVISIONAMIENTO HAPROXY----------------

echo "[[1]] ACTUALIZANDO EL SISTEMA"
sudo apt-get update -y

echo "[[3]] INSTALACION CLUSTER LXD"
sudo snap install lxd
sudo gpasswd -a vagrant lxd


# ------------------CONFIGURACIONES - FORMULARIO CREACION DE CLUSTER-------------
cat <<PRESEED | lxd init --preseed
config:
  core.https_address: 192.168.100.50:8443
  core.trust_password: vmhaproxy
networks:
- config:
    bridge.mode: fan
    fan.underlay_subnet: 192.168.100.0/24
  description: ""
  name: lxdfan0
  type: ""
  project: default
storage_pools:
- config: {}
  description: ""
  name: local
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdfan0
      type: nic
    root:
      path: /
      pool: local
      type: disk
  name: default
projects: []
cluster:
  server_name: vmhaproxy
  enabled: true
  member_config: []
  cluster_address: ""
  cluster_certificate: ""
  server_address: ""
  cluster_password: ""
  cluster_certificate_path: ""
  cluster_token: ""
PRESEED
#-------------------------------FIN CONFIGURACION FORMULARIO CLUSTER------------------

echo "[[4]] CREANDO CERTIFICADO CLUSTER"
sed ':a;N;$!ba;s/\n/\n\n/g' /var/snap/lxd/common/lxd/cluster.crt > /vagrant/certificado.crt


# Se crea contenedor haproxy en la maquina principal vmhaproxy
echo "[[5]] LANZANDO CONTENEDOR HAPROXY "
lxc launch ubuntu:20.04 haproxy --target vmhaproxy < /dev/null
sleep 20


# Se actualiza el sistema
# Instalamos haproxy dentro del contenedor haproxy
# Habilitamos haproxy
echo "[[6]] ACTUALIZANDO SISTEMA, INSTALANDO HAPROXY EN CONTENEDOR HAPROXY Y HABILITANDO HAPROXY "

lxc exec haproxy -- apt-get update
sudo lxc exec haproxy -- apt-get install haproxy -y
#sudo lxc exec haproxy -- systemctl enable haproxy



#------------------------------------CONFIGURACIÓN HAPROXY-------------------------------
echo "[[7]] CONFIGURACIÓN ARCHIVO haproxy.cfg"

cat <<EOF > /home/vagrant/haproxy.cfg
global
    log /dev/log local0
    log localhost local1 notice
    user haproxy
    group haproxy
    maxconn 2000
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    retries 3
    timeout connect 5000
    timeout client 50000
    timeout server 50000


backend servidoresweb
    balance roundrobin
    stats enable
    stats auth admin:admin
    stats uri /haproxy?stats
    option httpchk
    option forwardfor
    option http-server-close
    errorfile 503 /etc/haproxy/errors/503.http
    
    server web1 web1:80 check
    server web2 web2:80 check

frontend http
    bind *:80
#PARA ELASTICIDAD PUNTO EXTRA----------------------
    acl carga fe_sess_rate ge 100
    acl falla nbsrv(servidoresweb) eq 0
    use_backend servidoresbackup if carga
    use_backend servidoresbackup if falla
#-------------------------------------------------
    default_backend servidoresweb


backend servidoresbackup
    errorfile 503 /etc/haproxy/errors/503.http
    balance roundrobin
    stats enable
    stats auth admin:admin
    stats uri /haproxy?stats
    option httpchk
    option forwardfor
    option http-server-close

    server web3 web3backup:80 check
    server web4 web4backup:80 check
EOF
sleep 5
#----------------------------FIN CONFIGURACION haproxy.cfg------------------------

#Actualizamos haproxy.cfg con la configuración anterior
lxc file push haproxy.cfg haproxy/etc/haproxy/haproxy.cfg


echo "[[8]] REINICIANDO SERVICIO HAPROXY"
sudo lxc exec haproxy -- service haproxy restart
#sudo lxc exec haproxy -- systemctl start haproxy


echo "[[9]] REENVIO DE PUERTOS HAPROXY"
#lxc config device add haproxy http proxy listen=tcp:0.0.0.0:1080 connect=tcp:127.0.0.1:80
lxc config device add haproxy haproxyport proxy listen=tcp:0.0.0.0:80 connect=tcp:127.0.0.1:80


echo "[[10]] PAGINA DE ERROR"
cat <<EOF > /home/vagrant/503.http
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

#Contenido pagina de error
<html><body><h1>EN ESTE MOMENTO EL SERVICIO NO SE ENCUENTRA DISPONIBLE</h1>
LAMENTAMOS LOS INCONVENIENTES
INTENTE DE NUEVO EN UNOS MINUTOS
</body></html>
EOF

lxc file push /home/vagrant/503.http haproxy/etc/haproxy/errors/503.http

echo "CONFIGURACIÓN SERVIDOR HAproxy TERMINADO"
echo "APROVISIONAMIENTO HAproxy COMPLETO"

