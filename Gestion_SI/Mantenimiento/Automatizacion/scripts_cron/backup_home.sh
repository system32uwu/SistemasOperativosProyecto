#!/bin/bash
# $1 = tipo de respaldo
echo "$(date '+%d/%m/%Y %H:%M:%S'): Respaldando directorio HOME $1 " >> /logs/respaldos.log
rsync -e "ssh -p 49555" -arz /home root@192.168.0.5:/backup/Linux/ && echo "Directorio HOME respaldado con exito" >> /logs/respaldos.log || echo "Hubo errores respaldando directorio home" >> /logs/respaldos.log

ssh root@192.168.0.5 -p 49555 'cd /backup/Linux && git config --global user.email "overclodep@gmail.com" ; git config --global user.name "admin"'
ssh root@192.168.0.5 -p 49555 'cd /backup/Linux && sudo git add -A && sudo git commit -m "Respaldo HOME $1"'
#ejecuto rsync como usuario admin puesto que es el usuario que por defecto tiene copiada su clave ssh en el servidor de respaldos cuando ejecuto el script de automatizacion.
