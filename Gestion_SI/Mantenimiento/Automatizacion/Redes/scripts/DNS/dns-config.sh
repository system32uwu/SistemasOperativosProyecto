#!/bin/bash
#SCRIPT PARA AUTOMATIZAR LA CONFIGURACION DEL SERVIDOR DNS.
#ESTE SCRIPT NO DEBE SER EJECUTADO DIRECTAMENTE, ABRIR DESDE EL MENU PRINCIPAL.
#NOTA: en caso de estar usando un servicio virtualizado, el gateway del adaptador de red de la PC en la que esté corriendo esta máquina debe cambiarse a la especificada en la carpeta (192.168.0.1).

FOUND=$(cat /proc/net/dev | grep -v "lo" | grep ":") #verificar que haya conectado algun adaptador de red

if  [ -n "$FOUND" ] ; then
	echo "Adaptador(es) de red detectados: "
        echo $FOUND
else
	echo "No se encontraron adaptadores de red :(. Hace el favor de conectar el cable Ethernet."
	exit
fi

mi_interfaz="Mantenimiento/Automatizacion/Redes/configs/DNS/interface" #archivo preconfigurado de la interfaz
forward="Mantenimiento/Automatizacion/Redes/configs/DNS/forward.overclode.sibim" #zona forward
reverse="Mantenimiento/Automatizacion/Redes/configs/DNS/reverse.overclode.sibim" #zona reverse
namedconf="Mantenimiento/Automatizacion/Redes/configs/DNS/named.conf"
interfaz=$(ip a show | cut -d ' ' -f 2 | grep -v "lo"| sed '/^[[:space:]]*$/d' | head -n 1 | tr -d ':' ) #conseguimos el nombre de la interfaz

#rehago el symlink de la interfaz
ifdown $interfaz 
ifup $interfaz

#reinicio servicio
systemctl restart network


sed -i "/DEVICE=/c DEVICE=\"$interfaz\"" $mi_interfaz
sed -i "/NAME=/c NAME=\"$interfaz\"" $mi_interfaz

cat $mi_interfaz > /etc/sysconfig/network-scripts/ifcfg-$interfaz #sobreescribir el archivo

ifdown $interfaz
ifup $interfaz
systemctl restart network

#VERIFICAR SI TENGO INTERNET
test_conn=$(ping -c1 www.google.com | grep "100% packet loss")
if [[ -z "$test_conn" ]]; then
	echo "Red configurada con exito."
else
	echo "Hubieron errores configurando la red."
	exit
fi


echo "Limpiando cache..."; yum clean all &>/dev/null #borrar cache paquetes y demas para evitar conflictos
echo "Instalando FirewallD..."; yum install -q -y firewalld &>/dev/null
echo "Instalando BIND..."; yum install -q -y bind* &>/dev/null #instalar librerias de BIND

#cambiar hostname
hostnamectl set-hostname --static "OVERCLODE"

echo $namedconf > /etc/named.conf
cp $forward /var/named/
cp $reverse /var/named/

echo "OPTIONS=-"4"" >> /etc/sysconfig/named #para indicar que estamos usando IPv4

systemctl start named
systemctl enable named
firewall-cmd --zone=public --add-port=53/tcp --permanent
systemctl start firewalld
systemctl enable firewalld

named_status=$(systemctl show -p ActiveState named | cut -d "=" -f2)

if [ $named_status = "active" ]; then
	echo "Configurado BIND DNS con éxito."
else
	echo "Hubieron errores configurando el servicio DNS."
	exit
fi

firewalld_status=$(systemctl show -p ActiveState firewalld | cut -d "=" -f2)
if [ $firewalld_status = "active" ]; then
	echo "Agregada regla al firewall para el tráfico de datos del DNS."
else
	echo "Hubieron errores configurando el firewall."
fi


