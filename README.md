# RAGOSthinclient

**Infraestrutura de Thin Client com Arch Linux, KVM, PXE Boot, NFS e Samba AD Nativo**

## 📋 Visão Geral

Este repositório documenta a implementação completa da infraestrutura RAGOSthinclient, uma solução de thin client baseada em:

- **Hipervisor:** Arch Linux com KVM/QEMU e libvirt
- **Boot:** PXE (dnsmasq DHCP/TFTP + GRUB)
- **Sistema de Ficheiros:** NFS (Golden Image partilhada)
- **Autenticação:** Samba AD Nativo (domínio RAGOS.INTRA)
- **Desktop:** KDE Plasma com SDDM

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│ Host (inspiron) - Arch Linux + KVM/QEMU                     │
│ ├─ /srv/ragos-storage (virtiofs)                           │
│ └─ Redes libvirt:                                            │
│    ├─ default (192.168.122.0/24) - NAT Internet            │
│    └─ ragos-internal (10.0.3.0/24) - Rede Isolada          │
└─────────────────────────────────────────────────────────────┘
           │                                   │
           │                                   │
┌──────────▼─────────────────┐   ┌────────────▼────────────┐
│ VM RAGOS-SERVER            │   │ VM RAGOS-CLIENT-PXE     │
│ ├─ Samba AD DC             │   │ ├─ Diskless             │
│ ├─ DNS (Samba interno)     │   │ ├─ PXE Boot             │
│ ├─ DHCP/TFTP (dnsmasq)     │   │ ├─ NFS Root Mount       │
│ ├─ NFS Server              │   │ └─ KDE Plasma + SDDM    │
│ └─ IP: 10.0.3.1            │   │                          │
│                             │   │ Login: RAGOS\utilizador │
│ /mnt/ragostorage/nfs_root ──┼───┤ (via SSSD/Winbind)     │
│ (Golden Image)              │   │                          │
└─────────────────────────────┘   └──────────────────────────┘
```

## 📚 Documentação

### Guias Principais

- **[Adesão ao Domínio (Completo)](docs/domain-join-golden-image.md)** - Guia detalhado passo a passo para aderir a Golden Image ao domínio Samba AD
- **[Guia Rápido](docs/quick-reference.md)** - Referência rápida de comandos e troubleshooting

### Scripts Auxiliares

- **[prepare-golden-image-for-domain.sh](scripts/prepare-golden-image-for-domain.sh)** - Script automatizado para preparar a Golden Image
- **[verify-domain-join.sh](scripts/verify-domain-join.sh)** - Script de verificação da adesão ao domínio

### Exemplos de Configuração

- **[smb.conf (Cliente)](configs/samba/smb.conf.client-example)** - Configuração do Samba para cliente membro do domínio
- **[krb5.conf](configs/krb5.conf.example)** - Configuração do Kerberos
- **[sssd.conf](configs/sssd.conf.example)** - Configuração do SSSD (System Security Services Daemon)
- **[resolv.conf](configs/resolv.conf.example)** - Configuração do DNS

## 🚀 Quick Start

### Problema: `net ads join` falha com "Preauthentication failed"

Este é o problema mais comum ao tentar aderir a Golden Image ao domínio. A solução:

```bash
# 1. Entrar no chroot da Golden Image (no RAGOS-SERVER)
sudo arch-chroot /mnt/ragostorage/nfs_root

# 2. Executar o script de preparação
cd /path/to/ragos
./scripts/prepare-golden-image-for-domain.sh

# 3. Aderir ao domínio
net ads join -U administrator

# 4. Verificar a adesão
./scripts/verify-domain-join.sh
```

### Causa Raiz

O erro ocorre devido a:

1. **Relógio dessincronizado** - Kerberos exige sincronização de tempo (máx. 5 min de diferença)
2. **Falta de smb.conf** - O cliente precisa saber o realm e workgroup do domínio
3. **DNS não configurado** - O cliente precisa resolver registros SRV do AD

## 📖 Documentação Completa

Para implementação completa da infraestrutura (não apenas a adesão ao domínio), consulte:

- [Documentação Passo a Passo](docs/domain-join-golden-image.md)

## 🛠️ Componentes do Sistema

### Servidor (RAGOS-SERVER)

- **SO:** Arch Linux
- **IPs:** 
  - `enp1s0`: DHCP (rede default, acesso Internet)
  - `enp2s0`: 10.0.3.1/24 (rede ragos-internal)
- **Serviços:**
  - Samba AD DC (domínio: RAGOS.INTRA)
  - dnsmasq (DHCP: 10.0.3.100-200, TFTP)
  - NFS (exporta /mnt/ragostorage/nfs_root)
  - firewalld (zona internal)

### Golden Image

- **Localização:** `/mnt/ragostorage/nfs_root` (no servidor)
- **SO:** Arch Linux base
- **Desktop:** KDE Plasma + SDDM
- **Drivers:** virtio-gpu, virtio-net (KVM)
- **Estado:** Pronta para clientes thin client

### Cliente (RAGOS-CLIENT-PXE)

- **Boot:** PXE via dnsmasq
- **Sistema de Ficheiros:** NFS (monta /nfs_root do servidor)
- **Autenticação:** SSSD ou Winbind + PAM
- **Sessão:** KDE Plasma

## 🔍 Troubleshooting

### Erro: "Preauthentication failed"

```bash
# Verificar sincronização de relógio
date

# Re-sincronizar
sntp -s pool.ntp.org

# Tentar novamente
net ads join -U administrator
```

### Erro: "Failed to lookup DC info"

```bash
# Verificar DNS
host -t SRV _ldap._tcp.ragos.intra

# Se falhar, corrigir /etc/resolv.conf
cat > /etc/resolv.conf << 'EOF'
search ragos.intra
nameserver 10.0.3.1
EOF
```

### Erro: "DNS update failed"

```bash
# Adicionar registro A manualmente (fora do chroot)
sudo samba-tool dns add 127.0.0.1 ragos.intra ragos-client A 10.0.3.100 -U administrator
```

## 📝 Requisitos

### Host (Hipervisor)

- Arch Linux
- KVM/QEMU instalado
- libvirt configurado
- virtiofs suportado

### Servidor (VM)

- Arch Linux
- Samba 4.x (com suporte AD DC)
- dnsmasq
- nfs-utils
- firewalld

### Cliente (Golden Image)

- Arch Linux base
- KDE Plasma + SDDM
- samba (cliente)
- krb5
- ntp
- sssd (recomendado) ou winbind

## 🤝 Contribuir

Contribuições são bem-vindas! Para bugs, questões ou melhorias:

1. Abra uma issue descrevendo o problema/sugestão
2. Faça fork do repositório
3. Crie um branch para sua feature
4. Submeta um pull request

## 📄 Licença

Este projeto é documentação de código aberto, disponível para uso educacional e profissional.

## 👤 Autor

**RAGOS Agent** - Especialista em infraestrutura Arch Linux com KVM, PXE e Samba AD

---

**Última atualização:** 2025-11-17  
**Versão:** 1.0