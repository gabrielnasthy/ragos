#!/bin/bash

###############################################################################
# Script: cleanup-ragos.sh
# Descrição: Limpeza completa do ambiente RAGOSthinclient anterior
# Autor: RAGOS Agent
# Versão: 1.0
# Fase: 0 - Preparação do Host
#
# AVISO: Este script remove completamente VMs, redes e storage anteriores.
#        Execute apenas se tiver certeza de que deseja recomeçar.
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
# Início da Limpeza
###############################################################################

print_header "Iniciando Limpeza do Ambiente RAGOS"

print_warning "Este script irá remover:"
print_warning "  - VMs: RAGOS-SERVER, RAGOS-CLIENT-PXE"
print_warning "  - Rede: ragos-internal"
print_warning "  - Storage: /srv/ragos-storage (TODOS OS DADOS)"
print_warning "  - Bridges residuais"
echo ""
read -p "Deseja continuar? (sim/não): " CONFIRM

if [ "$CONFIRM" != "sim" ]; then
    print_info "Operação cancelada pelo utilizador"
    exit 0
fi

###############################################################################
# Remover VMs
###############################################################################

print_header "Removendo VMs"

for VM in RAGOS-SERVER RAGOS-CLIENT-PXE; do
    if virsh list --all | grep -q "$VM"; then
        print_info "Removendo VM: $VM"
        
        # Parar VM se estiver a correr
        if virsh list --state-running | grep -q "$VM"; then
            print_info "  Parando VM $VM..."
            virsh destroy "$VM" 2>/dev/null || true
            sleep 2
        fi
        
        # Remover VM e storage associado
        print_info "  Removendo definição e storage da VM $VM..."
        virsh undefine "$VM" --remove-all-storage 2>/dev/null || true
        
        print_success "VM $VM removida"
    else
        print_info "VM $VM não encontrada (já foi removida ou não existe)"
    fi
done

###############################################################################
# Remover Rede Virtual
###############################################################################

print_header "Removendo Rede Virtual"

if virsh net-list --all | grep -q "ragos-internal"; then
    print_info "Removendo rede ragos-internal"
    
    # Parar rede se estiver ativa
    if virsh net-list | grep -q "ragos-internal"; then
        print_info "  Parando rede ragos-internal..."
        virsh net-destroy ragos-internal 2>/dev/null || true
        sleep 1
    fi
    
    # Remover definição da rede
    print_info "  Removendo definição da rede..."
    virsh net-undefine ragos-internal 2>/dev/null || true
    
    print_success "Rede ragos-internal removida"
else
    print_info "Rede ragos-internal não encontrada (já foi removida ou não existe)"
fi

###############################################################################
# Remover Storage
###############################################################################

print_header "Removendo Storage"

STORAGE_DIR="/srv/ragos-storage"

if [ -d "$STORAGE_DIR" ]; then
    print_info "Removendo diretório $STORAGE_DIR"
    
    # Desmontar sistemas de ficheiros montados
    print_info "  Verificando pontos de montagem..."
    if mount | grep -q "$STORAGE_DIR"; then
        print_info "  Desmontando sistemas de ficheiros..."
        umount -R "$STORAGE_DIR" 2>/dev/null || true
        sleep 1
    fi
    
    # Verificar se há processos a usar o diretório
    if lsof "$STORAGE_DIR" 2>/dev/null; then
        print_warning "  Existem processos a usar $STORAGE_DIR"
        print_info "  Tentando terminar processos..."
        lsof -t "$STORAGE_DIR" 2>/dev/null | xargs -r kill -9 2>/dev/null || true
        sleep 1
    fi
    
    # Remover diretório
    print_info "  Removendo diretório e conteúdo..."
    rm -rf "$STORAGE_DIR"
    
    print_success "Storage removido"
else
    print_info "Diretório $STORAGE_DIR não encontrado (já foi removido ou não existe)"
fi

# Remover entrada do fstab se existir
if grep -q "$STORAGE_DIR" /etc/fstab 2>/dev/null; then
    print_info "Removendo entrada de $STORAGE_DIR do /etc/fstab"
    sed -i "\|$STORAGE_DIR|d" /etc/fstab
    print_success "Entrada do fstab removida"
fi

###############################################################################
# Remover Bridges Residuais
###############################################################################

print_header "Removendo Bridges Residuais"

if ip link show virbr1 2>/dev/null; then
    print_info "Removendo bridge virbr1"
    
    # Parar interface
    ip link set virbr1 down 2>/dev/null || true
    sleep 1
    
    # Remover bridge
    brctl delbr virbr1 2>/dev/null || ip link delete virbr1 2>/dev/null || true
    
    print_success "Bridge virbr1 removida"
else
    print_info "Bridge virbr1 não encontrada"
fi

###############################################################################
# Limpar Imagens de VM no Pool Padrão
###############################################################################

print_header "Limpando Imagens de VM"

for IMAGE in RAGOS-SERVER.qcow2 RAGOS-CLIENT-PXE.qcow2; do
    IMAGE_PATH="/var/lib/libvirt/images/$IMAGE"
    if [ -f "$IMAGE_PATH" ]; then
        print_info "Removendo imagem: $IMAGE_PATH"
        rm -f "$IMAGE_PATH"
        print_success "Imagem $IMAGE removida"
    fi
done

###############################################################################
# Verificação Final
###############################################################################

print_header "Verificação Final"

print_info "Verificando VMs restantes..."
REMAINING_VMS=$(virsh list --all | grep -c "RAGOS-" || true)
if [ "$REMAINING_VMS" -eq 0 ]; then
    print_success "Nenhuma VM RAGOS encontrada"
else
    print_warning "$REMAINING_VMS VM(s) RAGOS ainda encontrada(s)"
fi

print_info "Verificando redes restantes..."
if virsh net-list --all | grep -q "ragos-internal"; then
    print_warning "Rede ragos-internal ainda existe"
else
    print_success "Rede ragos-internal não encontrada"
fi

print_info "Verificando storage..."
if [ -d "$STORAGE_DIR" ]; then
    print_warning "Diretório $STORAGE_DIR ainda existe"
else
    print_success "Diretório $STORAGE_DIR não existe"
fi

###############################################################################
# Conclusão
###############################################################################

print_header "Limpeza Concluída"

print_success "Ambiente RAGOS limpo com sucesso!"
echo ""
print_info "Próximo passo: Execute setup-storage.sh para criar a estrutura de storage"
echo ""

exit 0
