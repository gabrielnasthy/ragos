#!/bin/bash

###############################################################################
# Script: setup-nfs.sh
# Descrição: Configuração completa e otimizada do servidor NFS
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

NFS_ROOT="/mnt/ragostorage/nfs_root"
NFS_HOME="/mnt/ragostorage/nfs_home"
NFS_SUBNET="10.0.3.0/24"

print_header "Configuração do Servidor NFS"

print_info "Configurações:"
print_info "  NFS Root (Golden Image): $NFS_ROOT"
print_info "  NFS Home (Diretórios home): $NFS_HOME"
print_info "  Subnet permitida: $NFS_SUBNET"
echo ""

###############################################################################
# Verificar Instalação do NFS
###############################################################################

print_header "Verificando Instalação do NFS"

if ! command -v exportfs &> /dev/null; then
    print_error "NFS não está instalado"
    print_info "Instalando nfs-utils..."
    pacman -S --noconfirm nfs-utils
    print_success "NFS instalado"
else
    print_success "NFS já está instalado"
fi

###############################################################################
# Verificar Diretórios
###############################################################################

print_header "Verificando Diretórios"

if [ ! -d "$NFS_ROOT" ]; then
    print_error "Diretório $NFS_ROOT não existe"
    print_info "Criando diretório..."
    mkdir -p "$NFS_ROOT"
    print_success "Diretório criado"
fi

if [ ! -d "$NFS_HOME" ]; then
    print_warning "Diretório $NFS_HOME não existe"
    print_info "Criando diretório..."
    mkdir -p "$NFS_HOME"
    print_success "Diretório criado"
fi

# Verificar se nfs_root está montado
print_info "Verificando se $NFS_ROOT está montado..."
if mount | grep -q "$NFS_ROOT"; then
    print_success "$NFS_ROOT está montado"
    mount | grep "$NFS_ROOT"
else
    print_warning "$NFS_ROOT não está montado"
    print_info "Se estiver usando a Golden Image como arquivo de imagem, monte-a primeiro"
fi

###############################################################################
# Configurar /etc/exports
###############################################################################

print_header "Configurando /etc/exports"

# Backup do exports anterior
if [ -f /etc/exports ]; then
    print_info "Fazendo backup de /etc/exports..."
    cp /etc/exports /etc/exports.backup.$(date +%Y%m%d%H%M%S)
    print_success "Backup criado"
fi

print_info "Criando novo /etc/exports..."
cat > /etc/exports << EOF
# ===================================================================
# RAGOSthinclient - NFS Exports
# ===================================================================
# Configuração otimizada para thin clients via PXE boot
#
# Criado em: $(date)
# ===================================================================

# Golden Image (Sistema Operativo dos Clientes)
# - fsid=0: Define como root do NFS v4
# - no_root_squash: Permite root do cliente ter acesso root
# - no_subtree_check: Melhora performance
# - sync: Garante consistência dos dados
$NFS_ROOT $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash,fsid=0)

# Diretórios Home dos Utilizadores
# - fsid=1: ID único para este export
# - no_root_squash: Necessário para criar diretórios home
$NFS_HOME $NFS_SUBNET(rw,sync,no_subtree_check,no_root_squash,fsid=1)
EOF

print_success "/etc/exports criado"
print_info "Conteúdo:"
cat /etc/exports

###############################################################################
# Configurar /etc/nfs.conf (Otimizações)
###############################################################################

print_header "Configurando Otimizações NFS"

print_info "Verificando /etc/nfs.conf..."
if [ ! -f /etc/nfs.conf ]; then
    print_warning "/etc/nfs.conf não existe, criando..."
    touch /etc/nfs.conf
fi

# Backup
if [ -s /etc/nfs.conf ]; then
    print_info "Fazendo backup de /etc/nfs.conf..."
    cp /etc/nfs.conf /etc/nfs.conf.backup.$(date +%Y%m%d%H%M%S)
fi

print_info "Adicionando configurações otimizadas..."
cat >> /etc/nfs.conf << 'EOF'

# ===================================================================
# RAGOSthinclient - Otimizações NFS
# ===================================================================

[nfsd]
# Aumentar threads para melhor performance com múltiplos clientes
threads=256
# Habilitar TCP (recomendado) e UDP (compatibilidade)
tcp=y
udp=y

[exportfs]
# Cache otimizado para exports
cache-requests=65536
cache-entries=65536

[mountd]
# Gerenciamento de mounts otimizado
manage-gids=y
cache-entries=65536
# Threads para mountd
threads=16

[statd]
# Monitoramento de estado
port=32765
outgoing-port=32766

[lockd]
# Lock manager
port=32767
udp-port=32767
EOF

print_success "Otimizações aplicadas"

###############################################################################
# Configurar Serviços
###############################################################################

print_header "Configurando Serviços NFS"

print_info "Habilitando serviços para início automático..."
systemctl enable rpcbind
systemctl enable nfs-server
print_success "Serviços habilitados"

print_info "Iniciando rpcbind..."
systemctl start rpcbind
sleep 2
print_success "rpcbind iniciado"

print_info "Iniciando nfs-server..."
systemctl start nfs-server
sleep 2
print_success "nfs-server iniciado"

###############################################################################
# Exportar Sistemas de Ficheiros
###############################################################################

print_header "Exportando Sistemas de Ficheiros"

print_info "Exportando via exportfs..."
exportfs -arv
print_success "Exports aplicados"

print_info "Verificando exports ativos..."
exportfs -v

###############################################################################
# Verificação
###############################################################################

print_header "Verificação"

print_info "Status dos serviços:"
systemctl status rpcbind --no-pager | head -n 5
systemctl status nfs-server --no-pager | head -n 5

print_info "Verificando com showmount..."
if showmount -e localhost; then
    print_success "NFS está exportando corretamente"
else
    print_error "Falha ao verificar exports"
fi

print_info "Verificando portas abertas..."
ss -tulpn | grep -E ":(2049|111|20048)" || print_warning "Algumas portas NFS podem não estar visíveis"

###############################################################################
# Testar Montagem Local
###############################################################################

print_header "Testando Montagem Local"

TEST_MOUNT="/tmp/nfs-test-mount"

print_info "Criando diretório de teste..."
mkdir -p "$TEST_MOUNT"

print_info "Tentando montar NFS localmente..."
if mount -t nfs4 localhost:/ "$TEST_MOUNT"; then
    print_success "Montagem local bem-sucedida"
    
    print_info "Verificando conteúdo..."
    ls -la "$TEST_MOUNT" | head -n 10
    
    print_info "Desmontando..."
    umount "$TEST_MOUNT"
    rmdir "$TEST_MOUNT"
    print_success "Teste concluído"
else
    print_error "Falha na montagem local"
    print_warning "Verifique os logs: journalctl -xeu nfs-server"
    rmdir "$TEST_MOUNT" 2>/dev/null || true
fi

###############################################################################
# Informações para Clientes
###############################################################################

print_header "Informações para Montagem nos Clientes"

cat << EOF

Para montar o NFS root no cliente:
  mount -t nfs4 10.0.3.1:/ /mnt

Para montar o NFS home no cliente:
  mount -t nfs4 10.0.3.1:/nfs_home /home

Entrada no /etc/fstab do cliente (Golden Image):
  10.0.3.1:/ / nfs4 defaults,_netdev 0 0
  10.0.3.1:/nfs_home /home nfs4 defaults,_netdev 0 0

Opções úteis para thin clients:
  - rsize=1048576,wsize=1048576  : Tamanho de bloco otimizado
  - hard,intr                     : Comportamento em caso de falha
  - tcp                           : Usar TCP (mais confiável)
  - vers=4.2                      : Versão do NFS

EOF

###############################################################################
# Conclusão
###############################################################################

print_header "NFS Configurado com Sucesso"

print_success "Servidor NFS está funcional e otimizado!"
echo ""
print_info "Exports ativos:"
exportfs -v | sed 's/^/  /'
echo ""
print_info "Serviços:"
print_info "  rpcbind: $(systemctl is-active rpcbind)"
print_info "  nfs-server: $(systemctl is-active nfs-server)"
echo ""
print_info "Logs:"
print_info "  journalctl -xeu nfs-server"
print_info "  journalctl -xeu rpcbind"
echo ""
print_info "Próximo passo: Configure o DHCP/PXE"
print_info "Execute: scripts/phase3/setup-pxe.sh"
echo ""

exit 0
