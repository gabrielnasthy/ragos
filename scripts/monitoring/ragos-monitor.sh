#!/bin/bash

###############################################################################
# Script: ragos-monitor.sh
# Descrição: Monitoramento em tempo real do ambiente RAGOSthinclient
# Autor: RAGOS Agent
# Versão: 1.0
#
# AVISO: Execute no RAGOS-SERVER para monitorar serviços
###############################################################################

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_section() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

check_service() {
    SERVICE=$1
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        echo -e "${GREEN}[✓] $SERVICE: ativo${NC}"
        return 0
    else
        echo -e "${RED}[✗] $SERVICE: inativo${NC}"
        return 1
    fi
}

###############################################################################
# Loop de Monitoramento
###############################################################################

while true; do
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     RAGOSthinclient - Monitor de Serviços                    ║${NC}"
    echo -e "${BLUE}║     Data/Hora: $(date +'%Y-%m-%d %H:%M:%S')                          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Serviços
    print_section "SERVIÇOS"
    check_service "samba"
    check_service "dnsmasq"
    check_service "nfs-server"
    check_service "firewalld"
    echo ""
    
    # Rede
    print_section "REDE"
    echo -e "${CYAN}Interface enp2s0 (ragos-internal):${NC}"
    ip addr show enp2s0 2>/dev/null | grep "inet " | awk '{print "  IP: " $2}' || echo "  ${RED}Interface não encontrada${NC}"
    echo ""
    
    # NFS
    print_section "NFS EXPORTS"
    if showmount -e localhost 2>/dev/null | grep -q "/mnt/ragostorage"; then
        showmount -e localhost 2>/dev/null | grep "/mnt/ragostorage" | while read line; do
            echo -e "  ${GREEN}✓${NC} $line"
        done
    else
        echo -e "  ${RED}✗ Nenhum export NFS ativo${NC}"
    fi
    echo ""
    
    # DHCP Leases
    print_section "DHCP LEASES"
    if [ -f /var/lib/dnsmasq/dnsmasq.leases ]; then
        LEASE_COUNT=$(wc -l < /var/lib/dnsmasq/dnsmasq.leases)
        echo -e "  Total de leases: ${GREEN}$LEASE_COUNT${NC}"
        if [ "$LEASE_COUNT" -gt 0 ]; then
            echo -e "  ${CYAN}Últimos 5 leases:${NC}"
            tail -n 5 /var/lib/dnsmasq/dnsmasq.leases | while read line; do
                IP=$(echo $line | awk '{print $3}')
                MAC=$(echo $line | awk '{print $2}')
                HOST=$(echo $line | awk '{print $4}')
                echo -e "    ${GREEN}•${NC} $IP ($MAC) - $HOST"
            done
        fi
    else
        echo -e "  ${YELLOW}! Arquivo de leases não encontrado${NC}"
    fi
    echo ""
    
    # Conexões NFS
    print_section "CLIENTES NFS CONECTADOS"
    NFS_CLIENTS=$(netstat -tn 2>/dev/null | grep ":2049" | grep "ESTABLISHED" | wc -l)
    if [ "$NFS_CLIENTS" -gt 0 ]; then
        echo -e "  ${GREEN}$NFS_CLIENTS cliente(s) conectado(s)${NC}"
        netstat -tn 2>/dev/null | grep ":2049" | grep "ESTABLISHED" | awk '{print "    • " $5}' | sed 's/:.*$//'
    else
        echo -e "  ${YELLOW}! Nenhum cliente conectado${NC}"
    fi
    echo ""
    
    # Domínio AD
    print_section "ACTIVE DIRECTORY"
    if systemctl is-active --quiet samba; then
        USERS=$(samba-tool user list 2>/dev/null | wc -l)
        echo -e "  ${GREEN}✓${NC} Domínio ativo"
        echo -e "  Utilizadores: ${GREEN}$USERS${NC}"
        
        # Testar DNS
        if host -t A ragos.intra 127.0.0.1 > /dev/null 2>&1; then
            echo -e "  DNS: ${GREEN}✓ Funcional${NC}"
        else
            echo -e "  DNS: ${RED}✗ Não está a resolver${NC}"
        fi
    else
        echo -e "  ${RED}✗ Samba não está ativo${NC}"
    fi
    echo ""
    
    # Storage
    print_section "STORAGE"
    if mount | grep -q "/mnt/ragostorage"; then
        USED=$(df -h /mnt/ragostorage/nfs_root 2>/dev/null | tail -1 | awk '{print $3}')
        AVAIL=$(df -h /mnt/ragostorage/nfs_root 2>/dev/null | tail -1 | awk '{print $4}')
        PERCENT=$(df -h /mnt/ragostorage/nfs_root 2>/dev/null | tail -1 | awk '{print $5}')
        
        echo -e "  Golden Image: ${GREEN}✓ Montada${NC}"
        echo -e "  Usado: $USED | Disponível: $AVAIL | Uso: $PERCENT"
    else
        echo -e "  ${RED}✗ Golden Image não está montada${NC}"
    fi
    echo ""
    
    # Sistema
    print_section "SISTEMA"
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    MEM=$(free -h | grep "Mem:" | awk '{print $3 "/" $2}')
    echo -e "  Load Average: ${CYAN}$LOAD${NC}"
    echo -e "  Memória: ${CYAN}$MEM${NC}"
    echo ""
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "  Pressione ${YELLOW}Ctrl+C${NC} para sair | Atualização a cada 5 segundos"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    sleep 5
done
