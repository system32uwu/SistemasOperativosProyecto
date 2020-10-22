#!/bin/bash
#SCRIPT PARA AUTOMATIZAR LA CONFIGURACION DEL SERVIDOR ARCHIVOS (principal).
#ESTE SCRIPT NO DEBE SER EJECUTADO DIRECTAMENTE, ABRIR DESDE EL MENU PRINCIPAL.
#NOTA: en caso de estar usando un servicio virtualizado, el gateway del adaptador de red de la PC en la que esté corriendo esta máquina debe cambiarse a la especificada en la carpeta (192.168.0.1).

./Mantenimiento/Automatizacion/UsuariosYGrupos/main.sh && echo "usuarios y grupos creados con exito."

mi_interfaz="Mantenimiento/Automatizacion/Redes/configs/ARCHIVOS/interface" #archivo preconfigurado de la interfaz
mi_ssh="Mantenimiento/Automatizacion/Redes/configs/ARCHIVOS/ssh"
FOUND=$(cat /proc/net/dev | grep -v "lo" | grep ":") #verificar que haya conectado algun adaptador de red

if  [ -n "$FOUND" ] ; then
	echo "Adaptador(es) de red detectados: "
        echo $FOUND
else
	echo "No se encontraron adaptadores de red :(. Hace el favor de conectar el cable Ethernet."
	exit
fi

interfaz=$(ip a show | cut -d ' ' -f 2 | grep -v "lo" | sed '/^[[:space:]]*$/d' | head -n 1 | tr -d ':' ) #conseguimos el nombre de la interfaz

#rehago el symlink de la interfaz
ifdown $interfaz 
ifup $interfaz

#reinicio servicio
systemctl restart network

sed -i "/DEVICE=/c DEVICE=\"$interfaz\"" $mi_interfaz
sed -i "/NAME=/c NAME=\"$interfaz\"" $mi_interfaz

cat $mi_interfaz > /etc/sysconfig/network-scripts/ifcfg-$interfaz #sobreescribir el archivo
hostnamectl set-hostname --static "ARCHIVOS"

ifdown $interfaz
ifup $interfaz
systemctl restart network

test_conn=$(ping -q -t 5 -w1 -c1 192.168.0.253 && grep "100% packet loss")
if [[ -z "$test_conn" ]]; then
	echo "Red configurada con exito."
else
	echo "Hubieron errores configurando la red. Verifique que el servidor DNS haya sido configurado y esté encendido."
	exit
fi


echo "Instalando ssh, rsync, crontab y firewalld."; yum install -q -y mysql-server openssh-server openssh-clients sshpass rsync crontab firewalld httpd &>/dev/null

systemctl start sshd
systemctl start firewalld
systemctl start httpd

sshd_status=$(systemctl show -p ActiveState sshd | cut -d "=" -f2)

if [[ $sshd_status = "active"  ]]; then
	echo "SSH instalado correctamente"
else
	echo "Hubieron errores instalando SSH."
	exit
fi

firewalld_status=$(systemctl show -p ActiveState firewalld | cut -d "=" -f2)

if [[ $firewalld_status = "active"  ]]; then
	echo "Firewalld instalado correctamente"
else
	echo "Hubieron errores instalando Firewalld."
	exit
fi

apache_status=$(systemctl show -p ActiveState httpd | cut -d "=" -f2)

if [[ $firewalld_status = "active"  ]]; then
	echo "Apache instalado correctamente"
else
	echo "Hubieron errores instalando Apache."
	exit
fi

firewall-cmd --permanent --zone=public --add-service=http
sudo firewall-cmd --permanent --zone=public --add-service=https #si tuvieramos pagina web sería buena idea tener un certificado SSL y https

systemctl enable sshd
systemctl enable firewalld
systemctl enable httpd

firewall-cmd --reload

sed -i "/SELINUX=enforcing/c SELINUX=disabled" /etc/sysconfig/selinux  #deshabilitar SELinux para poder usar rsync sin problemas

#genero clave ssh
su admin -c cat /dev/zero | ssh-keygen -q -N ""

adminpwd=$(grep -w "admin" Mantenimiento/Automatizacion/UsuariosYGrupos/ulist.txt | cut -d ":" -f2)
copiar_id=$(su admin -c sshpass -p "$adminpwd" ssh-copy-id "-p 49555" admin@192.168.0.250 | grep "denied\|ERROR")

if [[ -n "$copiar_id"  ]]; then
	echo "Error copiando la clave SSH, verifique que el servidor de respaldos este encendido y conectado"
	exit
fi

cat $mi_ssh > /etc/ssh/sshd_config  #aplico recien ahora la configuracion ya que sino no podia conectarme con usuario y contraseña, con esta configuracion habilitada solo se puede entrar con SSHKEY.
systemctl restart sshd

#este archivo guarda las credenciales y cada vez que efectuo mysqldump no tengo que especificar contrasena.

cp .my.cnf /home/admin/.my.cnf
chown admin: /home/admin/.my.cnf
chmod 600 ~/.my.cnf

#copio todos los scripts al directorio acordado
cp -R Mantenimiento/Automatizacion/scripts_cron /var/scripts_cron

#guardo la contrasena del usuario admin, cuando crontab ejecute comandos que requieran sudo paso la contrasena del usuario admin por stdin usando la contrasena que esta guardada en ese archivo
touch /var/creds.txt
chown admin: /var/creds.txt
chmod 600 /var/creds.txt
echo $adminpwd > /var/creds.txt

#copio el archivo de rutinas de cron
cp mis_rutinas /var/mis_rutinas
#asigno el archivo
crontab -u root /var/mis_rutinas