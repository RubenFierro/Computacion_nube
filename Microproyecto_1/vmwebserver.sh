
#archivo de aprovisionamiento webserver
echo "[[1]] ACTUALIZANDO SISTEMA"
sudo apt-get update -y


#NO NECESARIO
echo "[[2]] Agregando servidores a la ruta /etc/hosts file "
#echo '192.168.80.50 vmhaproxy  haproxy' | tee -a /etc/hosts
#echo '192.168.80.51 vmwebserver1  web1' | tee -a /etc/hosts
#echo '192.168.80.52 vmwebserver1  web2' | tee -a /etc/hosts


echo "[[3]] INSTALACIÓN CLUSTER LXD EN vmwebserver$1"
sudo snap install lxd
sudo gpasswd -a vagrant lxd


echo "[[4]] LXD INIT - LECTURA DE CERTIFICADO"
file=$(cat "/vagrant/certificado.crt")


#----------CONFIGURACION CLUSTER PRESEED PARA vmwebserver1 y vmwebserver2--------------------

cat <<PRESEED | sudo lxd init --preseed
config: {}
networks: []
storage_pools: []
profiles: []
projects: []
cluster:
  server_name: vmwebserver$1
  enabled: true
  member_config:
  - entity: storage-pool
    name: local
    key: source
    value: ""
    description: '"source" property for storage pool "local"'
  cluster_address: 192.168.100.50:8443
  cluster_certificate: "$file"
  server_address: 192.168.100.5$1:8443
  cluster_password: "vmhaproxy"
  cluster_certificate_path: ""
  cluster_token: ""
PRESEED
#-------------------------------FIN CONFIGURACION FORMULARIO CLUSTER------------------


# Se crea el primer contenedor lxd web1 y web2 dentro de la maquina vmwebserver1 y vmwebserver2 respectivamente
echo "[[5]] LANZANDO CONTENEDOR web$1"
lxc launch ubuntu:20.04 web$1 --target vmwebserver$1 < /dev/null
sleep 20


# Dentro de los contenedores creados, se actualiza SO
echo "[[6]] ACTUALIZANDO SO - INSTALANDO apache2 en contenedor web$1"
lxc exec web$1 -- apt-get update


#Instalamos apache en los contenedores web1 y web2
lxc exec web$1 -- apt-get install apache2 -y


#Configuracion index.html para contenedor web1 y web2
echo "[[7]] MODIFICACION APACHE index.html"

cat <<index > /home/vagrant/index.html
<!DOCTYPE html>
<html>
<body>
<h1>Bienvenidos al servidor web$1</h1>
</body>
</html>
index


#Se actualiza el index.html de los contenedores web1 y web2
lxc file push /home/vagrant/index.html web$1/var/www/html/index.html


#Reiniciamos apache en los contenedores web1 y web2
#lxc exec web$1 -- systemctl restart apache2


#Se reinicia apache en los contenedores
echo "[[8]] REINICIANDO apache2"
lxc exec web$1 -- service apache2 restart


#NO NECESARIO 
# Se redireccionan los puertos del contenedor hacia la VM para poder visualizar su contenido en la maquina host. 
#echo "[[9]] REENVIO DE PUERTOS"
#sudo lxc config device add web1 http proxy listen=tcp:0.0.0.0:2080 connect=tcp:127.0.0.1:80
#sudo lxc config device add web2 http proxy listen=tcp:0.0.0.0:3080 connect=tcp:127.0.0.1:80


#Si instrucciones anteriores terminan para web1 y web2, seguir con paso 9, de lo contrario no entra al if
#Creacion de contenedores de backup, 2 para cada maquina virtual secundaria

if [ "$1" -eq "2" ]; then
  
  echo "[[9]] CREANDO SERVIDORES BACKUP"
  lxc launch ubuntu:18.04 web3backup --target vmwebserver1 < /dev/null
  sleep 5
  lxc launch ubuntu:18.04 web4backup --target vmwebserver1 < /dev/null
  sleep 5

#Se actualiza SO e instala servidor apache en contenedores de backup
  echo "[[10]] ACTUALIZACION SO - INSTALACION APACHE SERVIDORES BACKUP"

  lxc exec web3backup -- apt-get update
  lxc exec web3backup -- apt-get install apache2 -y
  lxc exec web4backup -- apt-get update
  lxc exec web4backup -- apt-get install apache2 -y

#Se crean los index.html para servidores backup
  echo "[[11]] MODIFICACION APACHE index.html"

  cat <<index > /home/vagrant/index3.html
  <!DOCTYPE html>
  <html>
  <body>
  <h1>Bienvenidos al servidor web3backup</h1>
  </body>
  </html>  
index
  cat <<index > /home/vagrant/index4.html
  <!DOCTYPE html>
  <html>
  <body>
  <h1>Bienvenidos al servidor web4backup</h1>
  </body>
  </html>  
index

#Actualizacion index.html en servidores de backup
  lxc file push /home/vagrant/index3.html web3backup/var/www/html/index.html
  lxc file push /home/vagrant/index4.html web4backup/var/www/html/index.html

  lxc exec web3backup -- service apache2 restart
  lxc exec web4backup -- service apache2 restart


  echo "[[12]] REINICIANDO HAPROXY"
  lxc exec haproxy -- service haproxy restart

  echo "CONFIGURACIÓN MÁQUINA vmwebserver$1 TERMINADO"
  echo "APROVISIONAMIENTO vmwebserver$1 COMPLETO"

else
  echo "CONFIGURACIÓN MÁQUINA vmwebserver$1 TERMINADO"
  echo "APROVISIONAMIENTO vmwebserver$1 COMPLETO"
fi

