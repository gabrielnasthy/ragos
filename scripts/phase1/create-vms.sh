#!/bin/bash

###############################################################################
# Script: create-vms.sh
# Descrição: Criação automatizada das VMs RAGOS-SERVER e RAGOS-CLIENT-PXE
# Autor: RAGOS Agent
# Versão: 1.0
# Fase: 1 - Criação da Infraestrutura
#
# AVISO: Requer ISO do Arch Linux em /var/lib/libvirt/images/isos/
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

ISO_DIR="/var/lib/libvirt/images/isos"
ISO_PATH="${ISO_DIR}/archlinux.iso"
IMAGES_DIR="/var/lib/libvirt/images"
STORAGE_DIR="/srv/ragos-storage"

print_header "Criação das VMs RAGOSthinclient"

###############################################################################
# Verificações Pré-requisitos
###############################################################################

print_header "Verificando Pré-requisitos"

# Verificar se a rede ragos-internal existe
print_info "Verificando rede ragos-internal..."
if ! virsh net-list | grep -q "ragos-internal"; then
    print_error "Rede ragos-internal não está ativa"
    print_info "Execute: scripts/phase1/setup-network.sh"
    exit 1
fi
print_success "Rede ragos-internal está ativa"

# Verificar se o storage existe
print_info "Verificando storage em $STORAGE_DIR..."
if [ ! -d "$STORAGE_DIR" ]; then
    print_error "Diretório $STORAGE_DIR não existe"
    print_info "Execute: scripts/phase0/setup-storage.sh"
    exit 1
fi
print_success "Storage encontrado"

# Verificar ISO do Arch Linux
print_info "Verificando ISO do Arch Linux..."
if [ ! -f "$ISO_PATH" ]; then
    print_warning "ISO não encontrado em $ISO_PATH"
    print_info "Procurando ISOs disponíveis em $ISO_DIR..."
    
    if [ -d "$ISO_DIR" ]; then
        ls -lh "$ISO_DIR"/*.iso 2>/dev/null || print_warning "Nenhuma ISO encontrada"
    fi
    
    print_error "Por favor, baixe a ISO do Arch Linux e coloque em:"
    print_error "  $ISO_PATH"
    print_info ""
    print_info "Download: https://archlinux.org/download/"
    print_info "Comando: sudo wget -O $ISO_PATH 'URL_DA_ISO'"
    exit 1
fi
print_success "ISO encontrada: $ISO_PATH"

###############################################################################
# Criar RAGOS-SERVER
###############################################################################

print_header "Criando VM: RAGOS-SERVER"

# Verificar se já existe
if virsh list --all | grep -q "RAGOS-SERVER"; then
    print_warning "VM RAGOS-SERVER já existe"
    read -p "Deseja recriar? (sim/não): " RECREATE_SERVER
    
    if [ "$RECREATE_SERVER" == "sim" ]; then
        print_info "Removendo VM existente..."
        virsh destroy RAGOS-SERVER 2>/dev/null || true
        virsh undefine RAGOS-SERVER --remove-all-storage 2>/dev/null || true
        print_success "VM antiga removida"
    else
        print_info "Mantendo VM existente"
        SKIP_SERVER=true
    fi
fi

if [ "$SKIP_SERVER" != "true" ]; then
    print_info "Especificações da VM:"
    print_info "  Nome: RAGOS-SERVER"
    print_info "  Memória: 8GB"
    print_info "  CPUs: 4"
    print_info "  Disco: 50GB"
    print_info "  Redes: default (NAT) + ragos-internal"
    print_info "  Boot: UEFI"
    echo ""
    
    print_info "Criando VM RAGOS-SERVER..."
    virt-install \
        --name RAGOS-SERVER \
        --memory 8192 \
        --vcpus 4 \
        --cpu host-passthrough \
        --boot uefi \
        --os-variant archlinux \
        --cdrom "$ISO_PATH" \
        --disk path="${IMAGES_DIR}/RAGOS-SERVER.qcow2",size=50,bus=virtio,cache=writeback \
        --network network=default,model=virtio \
        --network network=ragos-internal,model=virtio \
        --graphics spice,listen=0.0.0.0 \
        --video qxl \
        --channel spicevmc \
        --memorybacking shared=yes \
        --filesystem source="${STORAGE_DIR}",target=ragos-storage,driver.type=virtiofs,accessmode=passthrough \
        --noautoconsole
    
    print_success "VM RAGOS-SERVER criada"
    
    print_info "Aguardando VM inicializar..."
    sleep 5
fi

###############################################################################
# Criar RAGOS-CLIENT-PXE
###############################################################################

print_header "Criando VM: RAGOS-CLIENT-PXE"

# Verificar se já existe
if virsh list --all | grep -q "RAGOS-CLIENT-PXE"; then
    print_warning "VM RAGOS-CLIENT-PXE já existe"
    read -p "Deseja recriar? (sim/não): " RECREATE_CLIENT
    
    if [ "$RECREATE_CLIENT" == "sim" ]; then
        print_info "Removendo VM existente..."
        virsh destroy RAGOS-CLIENT-PXE 2>/dev/null || true
        virsh undefine RAGOS-CLIENT-PXE 2>/dev/null || true
        print_success "VM antiga removida"
    else
        print_info "Mantendo VM existente"
        SKIP_CLIENT=true
    fi
fi

if [ "$SKIP_CLIENT" != "true" ]; then
    print_info "Especificações da VM:"
    print_info "  Nome: RAGOS-CLIENT-PXE"
    print_info "  Memória: 4GB"
    print_info "  CPUs: 2"
    print_info "  Disco: Nenhum (diskless)"
    print_info "  Rede: ragos-internal"
    print_info "  Boot: PXE + UEFI"
    echo ""
    
    print_info "Criando VM RAGOS-CLIENT-PXE..."
    virt-install \
        --name RAGOS-CLIENT-PXE \
        --memory 4096 \
        --vcpus 2 \
        --cpu host-passthrough \
        --boot "network,uefi" \
        --os-variant archlinux \
        --graphics spice,listen=0.0.0.0 \
        --video qxl \
        --disk none \
        --network network=ragos-internal,model=virtio \
        --noautoconsole
    
    print_success "VM RAGOS-CLIENT-PXE criada"
fi

###############################################################################
# Verificação
###############################################################################

print_header "Verificação das VMs"

print_info "Lista de VMs RAGOS:"
virsh list --all | grep "RAGOS-" || print_warning "Nenhuma VM RAGOS encontrada"

print_info "Status RAGOS-SERVER:"
virsh dominfo RAGOS-SERVER | grep -E "State|CPU|Memory"

print_info "Status RAGOS-CLIENT-PXE:"
virsh dominfo RAGOS-CLIENT-PXE | grep -E "State|CPU|Memory"

###############################################################################
# Instruções
###############################################################################

print_header "VMs Criadas com Sucesso"

print_success "VMs RAGOS-SERVER e RAGOS-CLIENT-PXE criadas!"
echo ""
print_info "Próximos passos:"
echo ""
print_info "1. Instalar Arch Linux no RAGOS-SERVER:"
print_info "   - Abra o console: sudo virt-manager"
print_info "   - Ou use: sudo virsh console RAGOS-SERVER"
print_info "   - Siga o processo normal de instalação do Arch"
print_info "   - Ou use o script automatizado (dentro da VM):"
print_info "     curl -O <URL>/scripts/phase2/arch-autoinstall.sh"
echo ""
print_info "2. Após instalação, configure o servidor:"
print_info "   - Faça SSH para o servidor"
print_info "   - Execute os scripts da phase3"
echo ""
print_info "3. NÃO inicie o RAGOS-CLIENT-PXE ainda!"
print_info "   - O cliente só funcionará após configurar PXE no servidor"
echo ""

# Criar arquivo de referência
cat > "${STORAGE_DIR}/vms-info.txt" << EOF
RAGOSthinclient - Informações das VMs
======================================

Data de Criação: $(date)

VM: RAGOS-SERVER
- Memória: 8GB
- CPUs: 4
- Disco: 50GB (/var/lib/libvirt/images/RAGOS-SERVER.qcow2)
- Redes: 
  * enp1s0 (default/NAT) - Acesso à Internet
  * enp2s0 (ragos-internal) - IP: 10.0.3.1
- Storage: /srv/ragos-storage (virtiofs)
- Função: Servidor AD + NFS + DHCP/PXE

VM: RAGOS-CLIENT-PXE
- Memória: 4GB
- CPUs: 2
- Disco: Nenhum (diskless)
- Rede: ragos-internal (obterá IP 10.0.3.100-200)
- Boot: PXE via UEFI
- Função: Cliente thin client

Comandos Úteis:
- Listar VMs: sudo virsh list --all
- Iniciar VM: sudo virsh start <nome>
- Parar VM: sudo virsh shutdown <nome>
- Forçar parar: sudo virsh destroy <nome>
- Console: sudo virsh console <nome>
- Info: sudo virsh dominfo <nome>

Estado Atual:
$(virsh list --all | grep "RAGOS-")
EOF

print_info "Informações salvas em: ${STORAGE_DIR}/vms-info.txt"

exit 0
