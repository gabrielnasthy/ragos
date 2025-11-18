#!/bin/bash

###############################################################################
# Script: ragos-diagnostic.sh
# Descrição: Diagnóstico completo do ambiente RAGOSthinclient
# Autor: RAGOS Agent
# Versão: 1.0
#
# AVISO: Execute no RAGOS-SERVER para diagnosticar problemas
###############################################################################

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

print_header() {
    echo -e "\n${BLUE}===================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}===================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
    TESTS_WARNING=$((TESTS_WARNING + 1))
}

print_info() {
    echo -e "${BLUE}[i] $1${NC}"
}

###############################################################################
# Diagnóstico
###############################################################################

print_header "DIAGNÓSTICO RAGOSthinclient"
print_info "Data/Hora: $(date)"
print_info "Hostname: $(hostname)"
echo ""

###############################################################################
# 1. Verificar Serviços
###############################################################################

print_header "1. VERIFICAÇÃO DE SERVIÇOS"

for service in samba dnsmasq nfs-server rpcbind firewalld; do
    print_info "Verificando $service..."
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_success "$service está ativo"
    else
        print_error "$service está inativo ou não instalado"
        print_info "  Comando: sudo systemctl start $service"
    fi
done

###############################################################################
# 2. Verificar Rede
###############################################################################

print_header "2. VERIFICAÇÃO DE REDE"

print_info "Verificando interface enp2s0..."
if ip addr show enp2s0 > /dev/null 2>&1; then
    if ip addr show enp2s0 | grep -q "10.0.3.1"; then
        print_success "Interface enp2s0 configurada (10.0.3.1)"
    else
        print_error "Interface enp2s0 existe mas não tem IP 10.0.3.1"
        ip addr show enp2s0 | grep "inet "
    fi
else
    print_error "Interface enp2s0 não encontrada"
fi

print_info "Verificando conectividade interna..."
if ping -c 1 -W 2 10.0.3.1 > /dev/null 2>&1; then
    print_success "Servidor responde a ping (10.0.3.1)"
else
    print_warning "Servidor não responde a ping"
fi

###############################################################################
# 3. Verificar NFS
###############################################################################

print_header "3. VERIFICAÇÃO NFS"

print_info "Verificando exports NFS..."
if showmount -e localhost 2>/dev/null | grep -q "/mnt/ragostorage"; then
    print_success "NFS exports configurados"
    showmount -e localhost 2>/dev/null | grep "/mnt/ragostorage" | while read line; do
        print_info "  Export: $line"
    done
else
    print_error "NFS exports não configurados ou NFS não está ativo"
    print_info "  Comando: sudo exportfs -arv"
fi

print_info "Verificando montagem da Golden Image..."
if mount | grep -q "/mnt/ragostorage/nfs_root"; then
    print_success "Golden Image está montada"
    df -h /mnt/ragostorage/nfs_root | tail -1
else
    print_error "Golden Image não está montada"
    print_info "  Comando: sudo mount /mnt/ragostorage/nfs_root"
fi

###############################################################################
# 4. Verificar DNS
###############################################################################

print_header "4. VERIFICAÇÃO DNS"

print_info "Verificando resolução local..."
if host -t A ragos.intra 127.0.0.1 > /dev/null 2>&1; then
    DNS_RESULT=$(host -t A ragos.intra 127.0.0.1 | grep "has address" | awk '{print $4}')
    print_success "DNS resolve ragos.intra para $DNS_RESULT"
else
    print_error "DNS não está a resolver ragos.intra"
    print_info "  Verifique: journalctl -xeu samba"
fi

print_info "Verificando registros SRV..."
if host -t SRV "_ldap._tcp.ragos.intra" 127.0.0.1 > /dev/null 2>&1; then
    print_success "Registros SRV encontrados"
else
    print_warning "Registros SRV não encontrados"
    print_info "  O DNS pode estar a inicializar ainda"
fi

###############################################################################
# 5. Verificar Kerberos
###############################################################################

print_header "5. VERIFICAÇÃO KERBEROS"

print_info "Verificando ticket Kerberos..."
if klist 2>/dev/null | grep -q "krbtgt"; then
    print_success "Ticket Kerberos válido encontrado"
    klist | grep "Default principal"
else
    print_warning "Nenhum ticket Kerberos ativo"
    print_info "  Para obter ticket: kinit administrator@RAGOS.INTRA"
fi

###############################################################################
# 6. Verificar PXE/DHCP
###############################################################################

print_header "6. VERIFICAÇÃO PXE/DHCP"

print_info "Verificando configuração dnsmasq..."
if [ -f /etc/dnsmasq.conf ]; then
    print_success "Arquivo /etc/dnsmasq.conf existe"
    
    if grep -q "dhcp-range" /etc/dnsmasq.conf; then
        DHCP_RANGE=$(grep "dhcp-range" /etc/dnsmasq.conf | head -1)
        print_info "  Range DHCP: $DHCP_RANGE"
    fi
    
    if grep -q "dhcp-boot" /etc/dnsmasq.conf; then
        DHCP_BOOT=$(grep "dhcp-boot" /etc/dnsmasq.conf | head -1)
        print_info "  Boot file: $DHCP_BOOT"
    fi
else
    print_error "Arquivo /etc/dnsmasq.conf não existe"
fi

print_info "Verificando servidor DHCP ativo..."
if netstat -ulpn 2>/dev/null | grep -q ":67"; then
    print_success "Servidor DHCP está a ouvir na porta 67"
else
    print_error "Servidor DHCP não está a ouvir"
fi

print_info "Verificando servidor TFTP ativo..."
if netstat -ulpn 2>/dev/null | grep -q ":69"; then
    print_success "Servidor TFTP está a ouvir na porta 69"
else
    print_error "Servidor TFTP não está a ouvir"
fi

print_info "Verificando arquivos PXE..."
if [ -f /mnt/ragostorage/tftp_root/EFI/BOOT/bootx64.efi ]; then
    print_success "Arquivo bootx64.efi encontrado"
else
    print_warning "Arquivo bootx64.efi não encontrado"
    print_info "  O PXE boot pode não funcionar"
fi

if [ -f /mnt/ragostorage/tftp_root/vmlinuz-linux ]; then
    print_success "Kernel Linux encontrado"
else
    print_warning "Kernel não encontrado em tftp_root"
fi

###############################################################################
# 7. Verificar Firewall
###############################################################################

print_header "7. VERIFICAÇÃO FIREWALL"

print_info "Verificando zonas firewalld..."
if firewall-cmd --list-all-zones > /dev/null 2>&1; then
    print_success "Firewalld está ativo"
    
    if firewall-cmd --get-active-zones | grep -q "ragos-internal"; then
        print_success "Zona ragos-internal ativa"
    else
        print_warning "Zona ragos-internal não está ativa"
    fi
else
    print_error "Firewalld não está ativo ou configurado"
fi

###############################################################################
# 8. Verificar Active Directory
###############################################################################

print_header "8. VERIFICAÇÃO ACTIVE DIRECTORY"

if systemctl is-active --quiet samba; then
    print_success "Samba AD está ativo"
    
    print_info "Verificando informações do domínio..."
    if samba-tool domain info 127.0.0.1 > /dev/null 2>&1; then
        print_success "Domínio está funcional"
        DOMAIN=$(samba-tool domain info 127.0.0.1 | grep "Domain" | head -1)
        print_info "  $DOMAIN"
    else
        print_error "Não foi possível obter informações do domínio"
    fi
    
    print_info "Verificando utilizadores..."
    USER_COUNT=$(samba-tool user list 2>/dev/null | wc -l)
    print_info "  Total de utilizadores: $USER_COUNT"
    
    print_info "Verificando grupos..."
    GROUP_COUNT=$(samba-tool group list 2>/dev/null | wc -l)
    print_info "  Total de grupos: $GROUP_COUNT"
else
    print_error "Samba não está ativo"
fi

###############################################################################
# 9. Verificar Storage
###############################################################################

print_header "9. VERIFICAÇÃO STORAGE"

print_info "Verificando diretório /srv/ragos-storage..."
if [ -d /srv/ragos-storage ]; then
    print_success "Diretório existe"
    
    for subdir in tftp_root nfs_root nfs_home samba_ad; do
        if [ -d "/srv/ragos-storage/$subdir" ]; then
            print_info "  ✓ $subdir/"
        else
            print_warning "  ✗ $subdir/ não existe"
        fi
    done
else
    print_error "Diretório /srv/ragos-storage não existe"
fi

print_info "Verificando virtiofs..."
if mount | grep -q "ragos-storage"; then
    print_success "Virtiofs montado"
    mount | grep "ragos-storage"
else
    print_warning "Virtiofs não está montado"
    print_info "  Verifique: /etc/fstab"
fi

###############################################################################
# 10. Verificar Sistema
###############################################################################

print_header "10. VERIFICAÇÃO DO SISTEMA"

print_info "Verificando relógio..."
print_info "  Data/Hora: $(date)"
print_info "  Timezone: $(timedatectl show -p Timezone --value)"

print_info "Verificando memória..."
MEM_TOTAL=$(free -h | grep "Mem:" | awk '{print $2}')
MEM_USED=$(free -h | grep "Mem:" | awk '{print $3}')
MEM_AVAIL=$(free -h | grep "Mem:" | awk '{print $7}')
print_info "  Total: $MEM_TOTAL | Usado: $MEM_USED | Disponível: $MEM_AVAIL"

print_info "Verificando disco..."
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}')
print_info "  Uso do disco /: $DISK_USAGE"

###############################################################################
# Resumo Final
###############################################################################

print_header "RESUMO DO DIAGNÓSTICO"

echo -e "${GREEN}Testes Passou: $TESTS_PASSED${NC}"
echo -e "${YELLOW}Avisos: $TESTS_WARNING${NC}"
echo -e "${RED}Testes Falharam: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_WARNING -eq 0 ]; then
    print_success "TODOS OS TESTES PASSARAM!"
    print_info "O ambiente RAGOSthinclient está completamente funcional"
    exit 0
elif [ $TESTS_FAILED -eq 0 ]; then
    print_warning "TESTES PASSARAM COM AVISOS"
    print_info "O ambiente está funcional mas existem questões menores"
    print_info "Reveja os avisos acima"
    exit 0
else
    print_error "ALGUNS TESTES FALHARAM"
    print_info "O ambiente pode não estar completamente funcional"
    print_info "Reveja os erros acima e corrija os problemas"
    echo ""
    print_info "Para ver logs detalhados:"
    print_info "  Samba: journalctl -xeu samba"
    print_info "  DNS: journalctl -xeu dnsmasq"
    print_info "  NFS: journalctl -xeu nfs-server"
    print_info "  Firewall: firewall-cmd --list-all-zones"
    exit 1
fi
