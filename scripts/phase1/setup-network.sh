#!/bin/bash

###############################################################################
# Script: setup-network.sh
# Descrição: Configuração da rede libvirt ragos-internal
# Autor: RAGOS Agent
# Versão: 1.0
# Fase: 1 - Criação da Infraestrutura
#
# AVISO: Cria a rede isolada para comunicação PXE/AD
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

NETWORK_NAME="ragos-internal"
NETWORK_SUBNET="10.0.3.0/24"
NETWORK_BRIDGE="virbr1"

print_header "Configuração da Rede Libvirt"

print_info "Configurações:"
print_info "  Nome da rede: $NETWORK_NAME"
print_info "  Subnet: $NETWORK_SUBNET"
print_info "  Bridge: $NETWORK_BRIDGE"
echo ""

###############################################################################
# Verificar se a Rede Já Existe
###############################################################################

print_header "Verificando Rede Existente"

if virsh net-list --all | grep -q "$NETWORK_NAME"; then
    print_warning "Rede $NETWORK_NAME já existe"
    read -p "Deseja recriar? (sim/não): " RECREATE
    
    if [ "$RECREATE" == "sim" ]; then
        print_info "Removendo rede existente..."
        
        if virsh net-list | grep -q "$NETWORK_NAME"; then
            virsh net-destroy "$NETWORK_NAME"
        fi
        
        virsh net-undefine "$NETWORK_NAME"
        print_success "Rede antiga removida"
    else
        print_info "Mantendo rede existente"
        print_info "Verificando estado da rede..."
        
        if virsh net-list | grep -q "$NETWORK_NAME"; then
            print_success "Rede $NETWORK_NAME já está ativa"
            virsh net-info "$NETWORK_NAME"
            exit 0
        else
            print_info "Rede existe mas não está ativa"
            print_info "Iniciando rede..."
            virsh net-start "$NETWORK_NAME"
            virsh net-autostart "$NETWORK_NAME"
            print_success "Rede iniciada"
            exit 0
        fi
    fi
fi

###############################################################################
# Criar Arquivo de Definição da Rede
###############################################################################

print_header "Criando Definição da Rede"

NETWORK_XML="/tmp/ragos-internal-network.xml"

print_info "Criando arquivo XML em $NETWORK_XML..."

cat > "$NETWORK_XML" << 'EOF'
<network>
  <name>ragos-internal</name>
  <bridge name='virbr1' stp='on' delay='0'/>
  <domain name='ragos.intra' localOnly='yes'/>
  <ip address='10.0.3.1' netmask='255.255.255.0'>
  </ip>
</network>
EOF

print_success "Arquivo XML criado"
print_info "Conteúdo:"
cat "$NETWORK_XML"

###############################################################################
# Definir e Iniciar a Rede
###############################################################################

print_header "Definindo e Iniciando Rede"

print_info "Definindo rede no libvirt..."
virsh net-define "$NETWORK_XML"
print_success "Rede definida"

print_info "Iniciando rede..."
virsh net-start "$NETWORK_NAME"
print_success "Rede iniciada"

print_info "Configurando início automático..."
virsh net-autostart "$NETWORK_NAME"
print_success "Início automático configurado"

###############################################################################
# Verificação
###############################################################################

print_header "Verificação"

print_info "Informações da rede:"
virsh net-info "$NETWORK_NAME"

print_info "Estado da rede:"
virsh net-list --all | grep "$NETWORK_NAME"

print_info "Verificando bridge $NETWORK_BRIDGE..."
if ip link show "$NETWORK_BRIDGE" > /dev/null 2>&1; then
    ip addr show "$NETWORK_BRIDGE"
    print_success "Bridge $NETWORK_BRIDGE criada"
else
    print_error "Bridge $NETWORK_BRIDGE não encontrada"
    exit 1
fi

###############################################################################
# Limpeza
###############################################################################

print_info "Removendo arquivo XML temporário..."
rm -f "$NETWORK_XML"

###############################################################################
# Conclusão
###############################################################################

print_header "Rede Configurada com Sucesso"

print_success "Rede $NETWORK_NAME criada e ativa!"
echo ""
print_info "Nome: $NETWORK_NAME"
print_info "Bridge: $NETWORK_BRIDGE"
print_info "Subnet: $NETWORK_SUBNET"
print_info "Início Automático: Sim"
echo ""
print_info "Próximo passo: Criar as VMs"
print_info "Execute: scripts/phase1/create-vms.sh"
echo ""

exit 0
