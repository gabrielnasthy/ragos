#!/bin/bash

###############################################################################
# Script: setup-pxe.sh
# Descrição: Configuração completa do DHCP/TFTP/PXE com dnsmasq
# Autor: RAGOS Agent
# Versão: 1.0
# Fase: 3 - Configuração dos Serviços no Servidor
#
# AVISO: Execute este script NO RAGOS-SERVER (via SSH)
###############################################################################

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}===================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}===================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[i] $1${NC}"
}

###############################################################################
# Verificação de Root
###############################################################################

if [ "$EUID" -ne 0 ]; then 
    print_error "Este script deve ser executado como root"
    print_info "Execute: sudo $0"
    exit 1
fi

###############################################################################
# Configurações
###############################################################################

INTERFACE="enp2s0"
SERVER_IP="10.0.3.1"
DHCP_RANGE_START="10.0.3.100"
DHCP_RANGE_END="10.0.3.200"
DHCP_NETMASK="255.255.255.0"
DHCP_LEASE_TIME="12h"
TFTP_ROOT="/mnt/ragostorage/tftp_root"
DOMAIN="ragos.intra"

print_header "Configuração DHCP/TFTP/PXE"

print_info "Configurações:"
print_info "  Interface: $INTERFACE"
print_info "  IP do servidor: $SERVER_IP"
print_info "  Range DHCP: $DHCP_RANGE_START - $DHCP_RANGE_END"
print_info "  TFTP Root: $TFTP_ROOT"
print_info "  Domínio: $DOMAIN"
echo ""

###############################################################################
# Verificar Instalação do dnsmasq
###############################################################################

print_header "Verificando Instalação do dnsmasq"

if ! command -v dnsmasq &> /dev/null; then
    print_error "dnsmasq não está instalado"
    print_info "Instalando dnsmasq..."
    pacman -S --noconfirm dnsmasq
    print_success "dnsmasq instalado"
else
    print_success "dnsmasq já está instalado"
fi

###############################################################################
# Parar systemd-resolved (Conflito de Porta 53)
###############################################################################

print_header "Verificando Conflitos de Serviços"

if systemctl is-active --quiet systemd-resolved; then
    print_warning "systemd-resolved está ativo (conflita com dnsmasq)"
    print_info "Parando systemd-resolved..."
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    print_success "systemd-resolved desativado"
fi

###############################################################################
# Verificar Diretório TFTP
###############################################################################

print_header "Verificando Diretório TFTP"

if [ ! -d "$TFTP_ROOT" ]; then
    print_warning "Diretório $TFTP_ROOT não existe"
    print_info "Criando diretório..."
    mkdir -p "$TFTP_ROOT"/{EFI/BOOT,pxelinux.cfg}
    print_success "Diretório criado"
fi

print_info "Configurando permissões do TFTP..."
chown -R nobody:nobody "$TFTP_ROOT"
chmod -R 755 "$TFTP_ROOT"
print_success "Permissões configuradas"

###############################################################################
# Configurar dnsmasq
###############################################################################

print_header "Configurando dnsmasq"

# Backup da configuração anterior
if [ -f /etc/dnsmasq.conf ]; then
    print_info "Fazendo backup de /etc/dnsmasq.conf..."
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup.$(date +%Y%m%d%H%M%S)
    print_success "Backup criado"
fi

print_info "Criando /etc/dnsmasq.conf..."
cat > /etc/dnsmasq.conf << EOF
# ===================================================================
# RAGOSthinclient - Configuração dnsmasq (DHCP/TFTP/PXE)
# ===================================================================
# Criado em: $(date)
# ===================================================================

# ===================================================================
# DNS - DESATIVADO (Samba gerencia o DNS)
# ===================================================================
port=0
no-resolv
no-hosts

# DNS upstream (para queries que não são do domínio)
server=8.8.8.8
server=8.8.4.4

# ===================================================================
# INTERFACE E BINDING
# ===================================================================
# Interface para escutar (rede ragos-internal)
interface=$INTERFACE
bind-interfaces

# ===================================================================
# DHCP
# ===================================================================
# Range de IPs para clientes
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,$DHCP_NETMASK,$DHCP_LEASE_TIME

# Gateway padrão (o próprio servidor)
dhcp-option=option:router,$SERVER_IP

# Netmask
dhcp-option=option:netmask,$DHCP_NETMASK

# DNS Server (Samba AD)
dhcp-option=option:dns-server,$SERVER_IP

# Nome do domínio
dhcp-option=option:domain-name,$DOMAIN

# ===================================================================
# PXE BOOT
# ===================================================================
# Arquivo de boot para UEFI
dhcp-boot=EFI/BOOT/bootx64.efi

# Habilitar servidor TFTP embutido
enable-tftp
tftp-root=$TFTP_ROOT

# Aumentar limite de conexões TFTP
tftp-max=100

# Segurança: Não permitir navegação para fora do tftp-root
tftp-secure

# ===================================================================
# LOGGING
# ===================================================================
# Habilitar logs de DHCP
log-dhcp

# Habilitar logs de queries DNS (mesmo com DNS desativado)
log-queries

# Arquivo de log
log-facility=/var/log/dnsmasq.log

# ===================================================================
# PERFORMANCE
# ===================================================================
# Máximo de leases DHCP
dhcp-lease-max=100

# Cache DNS (mesmo com DNS desativado, mantém cache interno)
cache-size=1000

# ===================================================================
# CONFIGURAÇÕES ADICIONAIS
# ===================================================================
# Não ler /etc/hosts
no-hosts

# Não ler /etc/resolv.conf para servidores DNS
no-resolv

# Não fazer polling de /etc/resolv.conf
no-poll

# PID file
pid-file=/run/dnsmasq/dnsmasq.pid
EOF

print_success "/etc/dnsmasq.conf criado"

###############################################################################
# Criar Diretório de PID
###############################################################################

print_info "Criando diretório para PID..."
mkdir -p /run/dnsmasq
print_success "Diretório criado"

###############################################################################
# Configurar Logging
###############################################################################

print_header "Configurando Logging"

print_info "Criando diretório de logs..."
mkdir -p /var/log
touch /var/log/dnsmasq.log
chmod 644 /var/log/dnsmasq.log
print_success "Log configurado"

###############################################################################
# Verificar Configuração
###############################################################################

print_header "Verificando Configuração"

print_info "Testando sintaxe da configuração..."
if dnsmasq --test; then
    print_success "Configuração válida"
else
    print_error "Configuração inválida"
    print_info "Execute: dnsmasq --test"
    exit 1
fi

###############################################################################
# Iniciar e Habilitar dnsmasq
###############################################################################

print_header "Iniciando Serviço dnsmasq"

print_info "Habilitando dnsmasq para início automático..."
systemctl enable dnsmasq
print_success "dnsmasq habilitado"

print_info "Iniciando dnsmasq..."
systemctl restart dnsmasq
sleep 2
print_success "dnsmasq iniciado"

print_info "Verificando status..."
systemctl status dnsmasq --no-pager | head -n 10

###############################################################################
# Verificação de Portas
###############################################################################

print_header "Verificação de Portas"

print_info "Verificando porta 67 (DHCP)..."
if ss -ulpn | grep -q ":67"; then
    print_success "Servidor DHCP está a ouvir na porta 67"
    ss -ulpn | grep ":67"
else
    print_error "DHCP não está a ouvir na porta 67"
fi

print_info "Verificando porta 69 (TFTP)..."
if ss -ulpn | grep -q ":69"; then
    print_success "Servidor TFTP está a ouvir na porta 69"
    ss -ulpn | grep ":69"
else
    print_error "TFTP não está a ouvir na porta 69"
fi

###############################################################################
# Verificar Leases
###############################################################################

print_header "Verificando DHCP Leases"

LEASES_FILE="/var/lib/dnsmasq/dnsmasq.leases"

print_info "Arquivo de leases: $LEASES_FILE"
if [ -f "$LEASES_FILE" ]; then
    print_success "Arquivo de leases existe"
    if [ -s "$LEASES_FILE" ]; then
        print_info "Leases ativos:"
        cat "$LEASES_FILE"
    else
        print_info "Nenhum lease ativo ainda (arquivo vazio)"
    fi
else
    print_warning "Arquivo de leases ainda não foi criado"
    print_info "Será criado quando o primeiro cliente se conectar"
fi

###############################################################################
# Informações para Clientes
###############################################################################

print_header "Informações de Boot PXE"

cat << EOF

Para os clientes bootarem via PXE, você precisa:

1. Ter os arquivos de boot no TFTP:
   - $TFTP_ROOT/EFI/BOOT/bootx64.efi
   - $TFTP_ROOT/vmlinuz-linux
   - $TFTP_ROOT/initramfs-linux.img
   - $TFTP_ROOT/EFI/BOOT/grub.cfg

2. A Golden Image deve estar pronta em:
   - /mnt/ragostorage/nfs_root

3. O cliente deve estar configurado para:
   - Boot via rede (PXE/UEFI)
   - Conectado à rede ragos-internal

Próximos passos:
- Configure o PXE boot completo com: scripts/phase5/setup-pxe-boot.sh
- Ou copie manualmente os arquivos de boot para $TFTP_ROOT

EOF

###############################################################################
# Conclusão
###############################################################################

print_header "DHCP/TFTP/PXE Configurado com Sucesso"

print_success "Servidor DHCP/TFTP está funcional!"
echo ""
print_info "Configurações:"
print_info "  Interface: $INTERFACE"
print_info "  IP: $SERVER_IP"
print_info "  Range DHCP: $DHCP_RANGE_START - $DHCP_RANGE_END"
print_info "  TFTP Root: $TFTP_ROOT"
echo ""
print_info "Serviço:"
print_info "  Status: $(systemctl is-active dnsmasq)"
print_info "  Logs: journalctl -xeu dnsmasq -f"
print_info "  Log file: /var/log/dnsmasq.log"
echo ""
print_info "Monitoramento:"
print_info "  Leases: cat $LEASES_FILE"
print_info "  Logs: tail -f /var/log/dnsmasq.log"
echo ""
print_info "Próximo passo: Configure os arquivos de boot PXE"
print_info "Execute: scripts/phase5/setup-pxe-boot.sh"
echo ""

exit 0
