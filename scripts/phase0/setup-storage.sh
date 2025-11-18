#!/bin/bash

###############################################################################
# Script: setup-storage.sh
# Descrição: Configuração completa da estrutura de storage RAGOSthinclient
# Autor: RAGOS Agent
# Versão: 1.0
# Fase: 0 - Preparação do Host
#
# AVISO: Este script cria a estrutura de diretórios e disco para a Golden Image
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

STORAGE_DIR="/srv/ragos-storage"
GOLDEN_IMAGE_SIZE="40G"

print_header "Configuração do Storage RAGOSthinclient"

print_info "Configurações:"
print_info "  Diretório base: $STORAGE_DIR"
print_info "  Tamanho da Golden Image: $GOLDEN_IMAGE_SIZE"
echo ""

###############################################################################
# Criar Estrutura de Diretórios
###############################################################################

print_header "Criando Estrutura de Diretórios"

print_info "Criando diretório base $STORAGE_DIR..."
mkdir -p "$STORAGE_DIR"
print_success "Diretório base criado"

print_info "Criando subdiretórios..."
mkdir -p "$STORAGE_DIR"/{tftp_root,nginx_root,nfs_root,nfs_home,samba_ad,logs,scripts,backups}
print_success "Estrutura de diretórios criada:"
tree -L 1 "$STORAGE_DIR" 2>/dev/null || ls -la "$STORAGE_DIR"

###############################################################################
# Criar Disco para Golden Image
###############################################################################

print_header "Criando Disco para Golden Image"

GOLDEN_IMAGE_PATH="${STORAGE_DIR}/golden-image.img"

if [ -f "$GOLDEN_IMAGE_PATH" ]; then
    print_warning "Arquivo $GOLDEN_IMAGE_PATH já existe"
    read -p "Deseja recriar? (sim/não): " RECREATE
    if [ "$RECREATE" == "sim" ]; then
        print_info "Removendo arquivo existente..."
        rm -f "$GOLDEN_IMAGE_PATH"
    else
        print_info "Mantendo arquivo existente"
        SKIP_IMAGE_CREATION=true
    fi
fi

if [ "$SKIP_IMAGE_CREATION" != "true" ]; then
    print_info "Criando disco sparse de $GOLDEN_IMAGE_SIZE..."
    qemu-img create -f raw "$GOLDEN_IMAGE_PATH" "$GOLDEN_IMAGE_SIZE"
    print_success "Disco criado: $GOLDEN_IMAGE_PATH"
    
    print_info "Formatando disco com ext4..."
    mkfs.ext4 -F "$GOLDEN_IMAGE_PATH"
    print_success "Disco formatado"
fi

###############################################################################
# Montar Golden Image
###############################################################################

print_header "Montando Golden Image"

NFS_ROOT="${STORAGE_DIR}/nfs_root"

if mount | grep -q "$NFS_ROOT"; then
    print_warning "$NFS_ROOT já está montado"
    print_info "Desmontando..."
    umount "$NFS_ROOT"
fi

print_info "Montando $GOLDEN_IMAGE_PATH em $NFS_ROOT..."
mount "$GOLDEN_IMAGE_PATH" "$NFS_ROOT"
print_success "Golden Image montada"

print_info "Verificando montagem..."
if mount | grep -q "$NFS_ROOT"; then
    mount | grep "$NFS_ROOT"
    print_success "Montagem confirmada"
else
    print_error "Falha na verificação da montagem"
    exit 1
fi

###############################################################################
# Configurar Permissões
###############################################################################

print_header "Configurando Permissões"

print_info "Configurando proprietário do TFTP..."
chown -R nobody:nobody "${STORAGE_DIR}/tftp_root"
print_success "TFTP: nobody:nobody"

print_info "Configurando permissões gerais..."
chmod -R 755 "$STORAGE_DIR"
print_success "Permissões configuradas"

# Permissões especiais para NFS home
chmod 755 "${STORAGE_DIR}/nfs_home"
print_success "NFS home: 755"

###############################################################################
# Configurar Montagem Automática (fstab)
###############################################################################

print_header "Configurando Montagem Automática"

FSTAB_ENTRY="$GOLDEN_IMAGE_PATH $NFS_ROOT ext4 loop,defaults 0 0"

if grep -q "$GOLDEN_IMAGE_PATH" /etc/fstab; then
    print_warning "Entrada já existe no /etc/fstab"
    print_info "Removendo entrada antiga..."
    sed -i "\|$GOLDEN_IMAGE_PATH|d" /etc/fstab
fi

print_info "Adicionando entrada ao /etc/fstab..."
echo "$FSTAB_ENTRY" >> /etc/fstab
print_success "Entrada adicionada ao fstab"

print_info "Conteúdo do fstab (entradas RAGOS):"
grep -i ragos /etc/fstab || print_warning "Nenhuma entrada RAGOS encontrada (isso é estranho)"

print_info "Testando montagem via fstab..."
umount "$NFS_ROOT"
mount "$NFS_ROOT"
if mount | grep -q "$NFS_ROOT"; then
    print_success "Montagem via fstab funciona corretamente"
else
    print_error "Falha na montagem via fstab"
    exit 1
fi

###############################################################################
# Criar Scripts Auxiliares
###############################################################################

print_header "Criando Scripts Auxiliares"

print_info "Criando script de montagem..."
cat > "${STORAGE_DIR}/scripts/mount-golden-image.sh" << 'EOF'
#!/bin/bash
# Script auxiliar para montar a Golden Image

GOLDEN_IMAGE="/srv/ragos-storage/golden-image.img"
MOUNT_POINT="/srv/ragos-storage/nfs_root"

if mount | grep -q "$MOUNT_POINT"; then
    echo "[i] Golden Image já está montada"
    exit 0
fi

echo "[i] Montando Golden Image..."
mount "$GOLDEN_IMAGE" "$MOUNT_POINT"

if mount | grep -q "$MOUNT_POINT"; then
    echo "[✓] Golden Image montada com sucesso"
else
    echo "[✗] Falha ao montar Golden Image"
    exit 1
fi
EOF

chmod +x "${STORAGE_DIR}/scripts/mount-golden-image.sh"
print_success "Script de montagem criado"

print_info "Criando script de desmontagem..."
cat > "${STORAGE_DIR}/scripts/umount-golden-image.sh" << 'EOF'
#!/bin/bash
# Script auxiliar para desmontar a Golden Image

MOUNT_POINT="/srv/ragos-storage/nfs_root"

if ! mount | grep -q "$MOUNT_POINT"; then
    echo "[i] Golden Image não está montada"
    exit 0
fi

echo "[i] Desmontando Golden Image..."
umount "$MOUNT_POINT"

if mount | grep -q "$MOUNT_POINT"; then
    echo "[✗] Falha ao desmontar Golden Image"
    echo "[i] Verificando processos que estão a usar o ponto de montagem..."
    lsof "$MOUNT_POINT" 2>/dev/null || fuser -v "$MOUNT_POINT" 2>/dev/null
    exit 1
else
    echo "[✓] Golden Image desmontada com sucesso"
fi
EOF

chmod +x "${STORAGE_DIR}/scripts/umount-golden-image.sh"
print_success "Script de desmontagem criado"

###############################################################################
# Criar Arquivo de Informações
###############################################################################

print_header "Criando Arquivo de Informações"

cat > "${STORAGE_DIR}/README.txt" << EOF
RAGOSthinclient - Storage Structure
===================================

Data de Criação: $(date)
Tamanho da Golden Image: $GOLDEN_IMAGE_SIZE

Estrutura de Diretórios:
- tftp_root/     : Arquivos de boot PXE (kernel, initramfs, grub)
- nginx_root/    : Arquivos web (futuro)
- nfs_root/      : Golden Image (sistema operativo dos clientes)
- nfs_home/      : Diretórios home dos utilizadores
- samba_ad/      : Dados do Active Directory Samba
- logs/          : Logs centralizados
- scripts/       : Scripts auxiliares
- backups/       : Backups da configuração

Golden Image:
- Arquivo: golden-image.img
- Formato: raw (sparse file)
- Sistema de Ficheiros: ext4
- Ponto de Montagem: nfs_root/
- Montagem Automática: Sim (via /etc/fstab)

Scripts Auxiliares:
- scripts/mount-golden-image.sh  : Montar manualmente a Golden Image
- scripts/umount-golden-image.sh : Desmontar manualmente a Golden Image

Próximos Passos:
1. Criar as VMs (RAGOS-SERVER e RAGOS-CLIENT-PXE)
2. Instalar o Arch Linux no RAGOS-SERVER
3. Configurar os serviços (AD, NFS, DHCP/PXE)
4. Criar a Golden Image (pacstrap no nfs_root/)
5. Configurar o boot PXE

Notas:
- O diretório nfs_root/ será exportado via NFS para os clientes
- O diretório tftp_root/ será servido pelo dnsmasq (TFTP)
- Não remova ou modifique a estrutura sem backup
EOF

print_success "Arquivo README.txt criado"

###############################################################################
# Verificação Final
###############################################################################

print_header "Verificação Final"

print_info "Estrutura de diretórios:"
tree -L 2 "$STORAGE_DIR" 2>/dev/null || find "$STORAGE_DIR" -maxdepth 2 -type d

print_info "Montagens:"
mount | grep "$STORAGE_DIR"

print_info "Espaço em disco:"
df -h "$NFS_ROOT"

print_info "Entrada no fstab:"
grep "$STORAGE_DIR" /etc/fstab

###############################################################################
# Conclusão
###############################################################################

print_header "Storage Configurado com Sucesso"

print_success "Estrutura de storage criada e pronta!"
echo ""
print_info "Localização: $STORAGE_DIR"
print_info "Golden Image: $GOLDEN_IMAGE_PATH"
print_info "Montagem: $NFS_ROOT"
echo ""
print_info "Próximo passo: Crie a rede libvirt e as VMs"
print_info "Execute: scripts/phase1/setup-network.sh"
print_info "Execute: scripts/phase1/create-vms.sh"
echo ""

exit 0
