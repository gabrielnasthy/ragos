# Guia de Instalação Completa RAGOSthinclient

## 📋 Visão Geral

Este guia detalha a implementação completa da infraestrutura RAGOSthinclient usando os scripts de automação fornecidos. O processo é dividido em 5 fases principais.

## 🎯 Arquitetura Final

```
┌─────────────────────────────────────────────────────────────────┐
│ Host (Arch Linux) - KVM/QEMU + libvirt                          │
│ └─ /srv/ragos-storage (compartilhado via virtiofs)             │
└─────────────────────────────────────────────────────────────────┘
           │                                        │
           ▼                                        ▼
┌──────────────────────────┐          ┌──────────────────────────┐
│ RAGOS-SERVER             │          │ RAGOS-CLIENT-PXE         │
│ ├─ Samba AD DC           │          │ ├─ Boot PXE/UEFI         │
│ ├─ DNS (Samba)           │          │ ├─ NFS Root              │
│ ├─ DHCP/TFTP (dnsmasq)   │          │ ├─ KDE Plasma            │
│ ├─ NFS Server            │◄─────────┤ └─ Autenticação AD       │
│ └─ IP: 10.0.3.1          │   NFS    │    (SSSD/Winbind)        │
└──────────────────────────┘          └──────────────────────────┘
```

## 📦 Pré-requisitos

### Hardware Mínimo

**Host (Hipervisor):**
- CPU: Intel/AMD com suporte a virtualização (VT-x/AMD-V)
- RAM: 16GB (mínimo 12GB)
- Disco: 100GB livres
- Rede: Interface Ethernet

**Recomendado:**
- CPU: 8+ cores
- RAM: 32GB
- Disco: SSD com 200GB+

### Software Necessário

No host (Arch Linux):

```bash
# Pacotes essenciais
sudo pacman -S qemu-full libvirt virt-manager virt-install \
               edk2-ovmf bridge-utils dnsmasq \
               ebtables iptables-nft dmidecode

# Iniciar e habilitar libvirt
sudo systemctl enable --now libvirtd
sudo systemctl enable --now virtlogd

# Adicionar utilizador ao grupo libvirt
sudo usermod -a -G libvirt $USER
newgrp libvirt
```

### ISO do Arch Linux

Baixe a ISO mais recente:

```bash
# Criar diretório para ISOs
sudo mkdir -p /var/lib/libvirt/images/isos

# Baixar ISO (substitua URL pela versão mais recente)
sudo wget -O /var/lib/libvirt/images/isos/archlinux.iso \
  'https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso'

# Verificar
ls -lh /var/lib/libvirt/images/isos/archlinux.iso
```

## 🚀 FASE 0: Preparação do Host

### Passo 1: Limpar Ambiente Anterior (Opcional)

Se você já tem um ambiente RAGOSthinclient anterior:

```bash
cd /path/to/ragos
sudo scripts/phase0/cleanup-ragos.sh
```

**⚠️ AVISO:** Este script remove **TODOS** os dados, VMs e redes anteriores!

### Passo 2: Criar Estrutura de Storage

```bash
sudo scripts/phase0/setup-storage.sh
```

**O que este script faz:**
- Cria `/srv/ragos-storage` com subdiretórios
- Cria disco sparse de 40GB para a Golden Image
- Monta a Golden Image em `/srv/ragos-storage/nfs_root`
- Configura montagem automática via `/etc/fstab`
- Cria scripts auxiliares de montagem

**Verificação:**

```bash
# Verificar estrutura
tree -L 2 /srv/ragos-storage

# Verificar montagem
mount | grep ragos-storage

# Verificar espaço
df -h /srv/ragos-storage/nfs_root
```

## 🏗️ FASE 1: Criação da Infraestrutura

### Passo 3: Criar Rede Virtual

```bash
sudo scripts/phase1/setup-network.sh
```

**O que este script faz:**
- Cria rede libvirt `ragos-internal`
- Configura subnet 10.0.3.0/24
- Cria bridge `virbr1`
- Habilita início automático

**Verificação:**

```bash
# Ver redes libvirt
sudo virsh net-list --all

# Ver informações da rede
sudo virsh net-info ragos-internal

# Ver bridge
ip addr show virbr1
```

### Passo 4: Criar VMs

```bash
sudo scripts/phase1/create-vms.sh
```

**O que este script faz:**
- Cria VM RAGOS-SERVER (8GB RAM, 4 CPUs, 50GB disco)
- Cria VM RAGOS-CLIENT-PXE (4GB RAM, 2 CPUs, sem disco)
- Configura redes e virtiofs
- Prepara para boot com ISO do Arch

**Verificação:**

```bash
# Listar VMs
sudo virsh list --all

# Ver informações
sudo virsh dominfo RAGOS-SERVER
sudo virsh dominfo RAGOS-CLIENT-PXE
```

## 💻 FASE 2: Instalação do Arch Linux no Servidor

### Passo 5: Instalar Arch no RAGOS-SERVER

#### Opção A: Via virt-manager (GUI)

```bash
sudo virt-manager
```

1. Selecione RAGOS-SERVER
2. Clique em "Abrir" para iniciar console
3. Siga instalação normal do Arch Linux

#### Opção B: Via virsh console (Terminal)

```bash
sudo virsh start RAGOS-SERVER
sudo virsh console RAGOS-SERVER
```

### Instalação Básica do Arch

**Importante:** Durante a instalação:

1. **Particionamento:**
   - `/dev/vda1`: 512MB, EFI System (FAT32)
   - `/dev/vda2`: Restante, Linux filesystem (ext4)

2. **Pacotes base:**
   ```bash
   pacstrap /mnt base linux linux-firmware linux-headers \
       intel-ucode amd-ucode nano sudo git curl wget \
       openssh networkmanager \
       samba krb5 nfs-utils dnsmasq firewalld \
       python-cryptography python-markdown python-dnspython \
       ntp chrony bind-tools
   ```

3. **Configuração de rede:**
   ```bash
   # No chroot
   arch-chroot /mnt
   
   # Hostname
   echo "ragos-server" > /etc/hostname
   
   # NetworkManager
   systemctl enable NetworkManager
   
   # Criar utilizador
   useradd -m -G wheel -s /bin/bash rocha
   passwd rocha
   
   # Sudo sem senha
   echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
   ```

4. **Bootloader (systemd-boot):**
   ```bash
   bootctl install
   
   # Configurar entries
   cat > /boot/loader/loader.conf << EOF
   default arch
   timeout 3
   editor 0
   EOF
   
   cat > /boot/loader/entries/arch.conf << EOF
   title Arch Linux
   linux /vmlinuz-linux
   initrd /intel-ucode.img
   initrd /amd-ucode.img
   initrd /initramfs-linux.img
   options root=/dev/vda2 rw quiet
   EOF
   ```

5. **Configurar virtiofs:**
   ```bash
   # Adicionar ao fstab
   echo "ragos-storage /mnt/ragostorage virtiofs defaults,noauto,x-systemd.automount,rw 0 0" >> /etc/fstab
   
   # Criar ponto de montagem
   mkdir -p /mnt/ragostorage
   ```

6. **SSH:**
   ```bash
   systemctl enable sshd
   ```

7. **Finalizar:**
   ```bash
   exit  # Sair do chroot
   umount -R /mnt
   reboot
   ```

### Passo 6: Configurar IP Estático

Após reboot, via console ou SSH:

```bash
# Criar configuração networkmanager
sudo nmcli connection add type ethernet \
    con-name ragos-internal \
    ifname enp2s0 \
    ip4 10.0.3.1/24

# Ativar conexão
sudo nmcli connection up ragos-internal

# Verificar
ip addr show enp2s0
```

## ⚙️ FASE 3: Configuração dos Serviços

### Passo 7: Configurar Active Directory

SSH para o servidor:

```bash
ssh rocha@10.0.3.1
cd /caminho/para/ragos
sudo scripts/phase3/setup-ad.sh
```

**O que este script faz:**
- Para systemd-resolved
- Configura DNS estático
- Provisiona domínio RAGOS.INTRA
- Configura Kerberos
- Inicia e habilita Samba
- Testa autenticação

**Senha do Administrator:** `RAG200519@.rocha`

**Verificação:**

```bash
# Status do Samba
sudo systemctl status samba

# Testar Kerberos
sudo kinit administrator@RAGOS.INTRA
klist

# Testar DNS
host -t A ragos.intra
host -t SRV _ldap._tcp.ragos.intra

# Info do domínio
sudo samba-tool domain info 127.0.0.1

# Listar utilizadores
sudo samba-tool user list
```

### Passo 8: Configurar NFS

```bash
sudo scripts/phase3/setup-nfs.sh
```

**O que este script faz:**
- Configura `/etc/exports`
- Otimiza `/etc/nfs.conf`
- Inicia serviços NFS
- Testa montagem local

**Verificação:**

```bash
# Ver exports
sudo exportfs -v

# Testar com showmount
showmount -e localhost

# Status
sudo systemctl status nfs-server
```

### Passo 9: Configurar DHCP/PXE

```bash
sudo scripts/phase3/setup-pxe.sh
```

**O que este script faz:**
- Configura dnsmasq (DHCP + TFTP)
- Define range de IPs (10.0.3.100-200)
- Habilita servidor TFTP
- Configura logging

**Verificação:**

```bash
# Status
sudo systemctl status dnsmasq

# Ver portas
sudo ss -ulpn | grep -E ":(67|69)"

# Ver logs
sudo tail -f /var/log/dnsmasq.log
```

### Passo 10: Configurar Firewall

```bash
# Configuração manual do firewall
sudo systemctl enable --now firewalld

# Criar zona ragos-internal
sudo firewall-cmd --permanent --new-zone=ragos-internal
sudo firewall-cmd --permanent --zone=ragos-internal --change-interface=enp2s0

# Adicionar serviços
sudo firewall-cmd --permanent --zone=ragos-internal --set-target=ACCEPT
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=dhcp
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=tftp
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=dns
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=kerberos
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=ldap
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=ldaps
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=nfs
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=nfs3
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=mountd
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=rpc-bind
sudo firewall-cmd --permanent --zone=ragos-internal --add-service=samba
sudo firewall-cmd --permanent --zone=ragos-internal --add-port=2049/tcp

# Recarregar
sudo firewall-cmd --reload

# Verificar
sudo firewall-cmd --list-all-zones
```

## 🖼️ FASE 4: Criação da Golden Image

### Passo 11: Instalar Sistema Base na Golden Image

```bash
# No servidor RAGOS-SERVER
sudo pacstrap /mnt/ragostorage/nfs_root base linux linux-firmware \
    networkmanager wpa_supplicant \
    mesa xf86-video-qxl \
    plasma-desktop sddm \
    firefox konsole dolphin \
    sudo nano vim htop \
    samba krb5 sssd ntp \
    mkinitcpio-nfs-utils nfs-utils
```

### Passo 12: Configurar Golden Image

```bash
# Entrar no chroot
sudo arch-chroot /mnt/ragostorage/nfs_root

# Hostname
echo "ragos-client" > /etc/hostname

# Locale
echo "pt_BR.UTF-8 UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf

# Timezone
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime

# Habilitar serviços
systemctl enable NetworkManager
systemctl enable sddm

# Sair
exit
```

### Passo 13: Aderir ao Domínio

```bash
# Entrar no chroot
sudo arch-chroot /mnt/ragostorage/nfs_root

# Executar script de preparação
cd /caminho/para/ragos
./scripts/prepare-golden-image-for-domain.sh

# Aderir ao domínio
net ads join -U administrator

# Verificar
./scripts/verify-domain-join.sh

# Sair
exit
```

## 🚀 FASE 5: Configuração do Boot PXE

### Passo 14: Copiar Arquivos de Boot

```bash
# No servidor
TFTP_ROOT="/mnt/ragostorage/tftp_root"
GOLDEN_ROOT="/mnt/ragostorage/nfs_root"

# Copiar kernel e initramfs
sudo cp $GOLDEN_ROOT/boot/vmlinuz-linux $TFTP_ROOT/
sudo cp $GOLDEN_ROOT/boot/initramfs-linux.img $TFTP_ROOT/

# Instalar GRUB no chroot
sudo arch-chroot $GOLDEN_ROOT pacman -S --noconfirm grub efibootmgr
```

### Passo 15: Criar Configuração do GRUB

```bash
# Criar grub.cfg
sudo mkdir -p $TFTP_ROOT/EFI/BOOT

sudo cat > $TFTP_ROOT/EFI/BOOT/grub.cfg << 'EOF'
set timeout=5
set default=0

menuentry "RAGOS Thin Client - NFS Boot" {
    echo "Carregando kernel..."
    linux /vmlinuz-linux ip=dhcp root=/dev/nfs nfsroot=10.0.3.1:/mnt/ragostorage/nfs_root,vers=4.2,tcp,rw quiet splash
    echo "Carregando initramfs..."
    initrd /initramfs-linux.img
}
EOF

# Gerar bootx64.efi
sudo arch-chroot $GOLDEN_ROOT grub-mkstandalone \
    -O x86_64-efi \
    --modules="part_gpt part_msdos nfs tftp http" \
    -o $TFTP_ROOT/EFI/BOOT/bootx64.efi \
    "boot/grub/grub.cfg=$TFTP_ROOT/EFI/BOOT/grub.cfg"

# Ajustar permissões
sudo chown -R nobody:nobody $TFTP_ROOT
sudo chmod -R 755 $TFTP_ROOT
```

## ✅ Verificação e Testes

### Monitoramento em Tempo Real

```bash
# No servidor
sudo scripts/monitoring/ragos-monitor.sh
```

### Diagnóstico Completo

```bash
sudo scripts/monitoring/ragos-diagnostic.sh
```

### Testar Boot do Cliente

1. No host, inicie o cliente:
   ```bash
   sudo virsh start RAGOS-CLIENT-PXE
   sudo virt-manager  # Para ver console
   ```

2. O cliente deve:
   - Obter IP via DHCP (10.0.3.100-200)
   - Baixar bootx64.efi via TFTP
   - Carregar kernel e initramfs
   - Montar NFS root
   - Iniciar KDE Plasma

3. Login:
   - Utilizador: `administrator@ragos.intra`
   - Password: `RAG200519@.rocha`

## 🔧 Troubleshooting

### Problema: Cliente não obtém IP

```bash
# No servidor, verificar dnsmasq
sudo systemctl status dnsmasq
sudo tail -f /var/log/dnsmasq.log

# Verificar firewall
sudo firewall-cmd --list-all-zones | grep -A 20 ragos-internal
```

### Problema: TFTP timeout

```bash
# Verificar arquivos TFTP
ls -la /mnt/ragostorage/tftp_root/EFI/BOOT/

# Verificar permissões
sudo chown -R nobody:nobody /mnt/ragostorage/tftp_root
sudo chmod -R 755 /mnt/ragostorage/tftp_root
```

### Problema: NFS mount failed

```bash
# Verificar exports
sudo exportfs -v

# Testar montagem local
sudo mount -t nfs4 localhost:/ /tmp/test
```

### Problema: Login AD falha

```bash
# No chroot da Golden Image
sudo arch-chroot /mnt/ragostorage/nfs_root

# Verificar
./scripts/verify-domain-join.sh

# Re-aderir se necessário
net ads leave -U administrator
net ads join -U administrator
```

## 📚 Referências

- [Arch Linux Wiki - PXE](https://wiki.archlinux.org/title/PXE)
- [Arch Linux Wiki - NFS](https://wiki.archlinux.org/title/NFS)
- [Samba Wiki - Active Directory](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [Documentação RAGOSthinclient](../README.md)

---

**Última atualização:** 2025-11-18  
**Versão:** 1.0
