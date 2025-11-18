# RAGOSthinclient - Scripts de Automação

Este diretório contém todos os scripts de automação para implementação completa da infraestrutura RAGOSthinclient.

## 📁 Estrutura de Diretórios

```
scripts/
├── phase0/              # Preparação do Host
│   ├── cleanup-ragos.sh        # Limpeza completa do ambiente
│   └── setup-storage.sh        # Configuração da estrutura de storage
├── phase1/              # Criação da Infraestrutura
│   ├── setup-network.sh        # Configuração da rede libvirt
│   └── create-vms.sh           # Criação automatizada das VMs
├── phase2/              # Instalação do Servidor (futuro)
│   ├── arch-autoinstall.sh     # Instalação automatizada do Arch
│   └── chroot-config.sh        # Configuração dentro do chroot
├── phase3/              # Configuração dos Serviços
│   ├── setup-ad.sh             # Configuração do Active Directory
│   ├── setup-network-server.sh # Rede e firewall do servidor
│   ├── setup-nfs.sh            # Servidor NFS otimizado
│   └── setup-pxe.sh            # Configuração DHCP/PXE
├── phase4/              # Golden Image (futuro)
│   ├── create-golden-image.sh  # Criação da Golden Image
│   └── configure-ad-client.sh  # Cliente AD na Golden Image
├── phase5/              # Boot PXE (futuro)
│   ├── setup-pxe-boot.sh       # Configuração completa do PXE
│   └── finalize-setup.sh       # Finalização e testes
├── monitoring/          # Ferramentas de Monitoramento
│   ├── ragos-monitor.sh        # Monitor em tempo real
│   └── ragos-diagnostic.sh     # Diagnóstico completo
├── prepare-golden-image-for-domain.sh  # Preparação para adesão ao domínio
└── verify-domain-join.sh              # Verificação da adesão
```

## 🚀 Ordem de Execução

### FASE 0: Preparação do Host (Executar no Host)

```bash
# 1. Limpar ambiente anterior (CUIDADO: Remove tudo!)
sudo scripts/phase0/cleanup-ragos.sh

# 2. Criar estrutura de storage
sudo scripts/phase0/setup-storage.sh
```

### FASE 1: Criação da Infraestrutura (Executar no Host)

```bash
# 3. Criar rede libvirt ragos-internal
sudo scripts/phase1/setup-network.sh

# 4. Criar VMs RAGOS-SERVER e RAGOS-CLIENT-PXE
sudo scripts/phase1/create-vms.sh
```

### FASE 2: Instalação do Servidor

Após criar as VMs, você precisa instalar o Arch Linux no RAGOS-SERVER:

```bash
# 5. Abrir console da VM
sudo virt-manager
# OU
sudo virsh console RAGOS-SERVER

# 6. Instalar Arch Linux manualmente ou usar script automatizado
# (Scripts da phase2 ainda serão desenvolvidos)
```

### FASE 3: Configuração dos Serviços (Executar no RAGOS-SERVER via SSH)

```bash
# Fazer SSH para o servidor
ssh rocha@<IP-DO-SERVIDOR>

# 7. Configurar Active Directory
sudo scripts/phase3/setup-ad.sh

# 8. Configurar rede e firewall (futuro)
# sudo scripts/phase3/setup-network-server.sh

# 9. Configurar NFS (futuro)
# sudo scripts/phase3/setup-nfs.sh

# 10. Configurar DHCP/PXE (futuro)
# sudo scripts/phase3/setup-pxe.sh
```

### FASE 4-5: Golden Image e PXE Boot

Scripts para criar a Golden Image e configurar o boot PXE serão desenvolvidos nas fases 4 e 5.

### Monitoramento (Executar no RAGOS-SERVER)

```bash
# Monitor em tempo real (atualiza a cada 5 segundos)
sudo scripts/monitoring/ragos-monitor.sh

# Diagnóstico completo (executa uma vez)
sudo scripts/monitoring/ragos-diagnostic.sh
```

## 📋 Scripts Detalhados

### Phase 0: Preparação

#### cleanup-ragos.sh
Remove completamente o ambiente RAGOSthinclient anterior:
- VMs (RAGOS-SERVER, RAGOS-CLIENT-PXE)
- Rede virtual (ragos-internal)
- Storage (/srv/ragos-storage)
- Bridges residuais

**⚠️ AVISO:** Este script remove **TODOS OS DADOS**. Use apenas se tiver certeza.

#### setup-storage.sh
Cria a estrutura completa de storage:
- Diretório base `/srv/ragos-storage`
- Subdiretórios (tftp_root, nfs_root, nfs_home, etc.)
- Disco sparse de 40GB para Golden Image
- Montagem automática via fstab
- Scripts auxiliares de montagem/desmontagem

### Phase 1: Infraestrutura

#### setup-network.sh
Cria e configura a rede libvirt:
- Nome: ragos-internal
- Subnet: 10.0.3.0/24
- Bridge: virbr1
- Modo: Isolado (sem NAT)

#### create-vms.sh
Cria as duas VMs principais:

**RAGOS-SERVER:**
- Memória: 8GB
- CPUs: 4
- Disco: 50GB
- Redes: default (NAT) + ragos-internal
- Virtiofs: /srv/ragos-storage

**RAGOS-CLIENT-PXE:**
- Memória: 4GB
- CPUs: 2
- Disco: Nenhum (diskless)
- Rede: ragos-internal
- Boot: PXE + UEFI

### Phase 3: Serviços

#### setup-ad.sh
Configura o Active Directory Samba completo:
- Para systemd-resolved
- Configura DNS estático
- Provisiona domínio RAGOS.INTRA
- Configura Kerberos
- Otimiza performance
- Testa autenticação

**Configurações:**
- Realm: RAGOS.INTRA
- Workgroup: RAGOS
- Função: Domain Controller
- Password: RAG200519@.rocha

### Monitoramento

#### ragos-monitor.sh
Monitor em tempo real que mostra:
- Status dos serviços (Samba, dnsmasq, NFS, firewalld)
- Configuração de rede
- Exports NFS ativos
- DHCP leases
- Clientes conectados
- Informações do AD
- Uso de storage e sistema

**Uso:** Deixe rodando em um terminal separado para monitorar o ambiente.

#### ragos-diagnostic.sh
Diagnóstico completo que verifica:
1. Serviços (samba, dnsmasq, nfs-server, etc.)
2. Rede (interfaces, conectividade)
3. NFS (exports, montagens)
4. DNS (resolução, registros SRV)
5. Kerberos (tickets)
6. PXE/DHCP (configuração, arquivos)
7. Firewall (zonas, regras)
8. Active Directory (domínio, utilizadores)
9. Storage (diretórios, virtiofs)
10. Sistema (relógio, memória, disco)

**Saída:** Relatório detalhado com contadores de sucesso/falha/aviso.

## 🎯 Scripts Existentes (Já Implementados)

### prepare-golden-image-for-domain.sh
Prepara a Golden Image para aderir ao domínio:
- Sincroniza relógio via NTP
- Configura DNS
- Cria smb.conf e krb5.conf
- Testa autenticação Kerberos

**Uso:** Executar DENTRO do chroot da Golden Image
```bash
sudo arch-chroot /mnt/ragostorage/nfs_root
./scripts/prepare-golden-image-for-domain.sh
net ads join -U administrator
```

### verify-domain-join.sh
Verifica se a adesão ao domínio foi bem-sucedida:
- Verifica keytab
- Testa DNS
- Valida configurações Samba/SSSD
- Testa Winbind
- Verifica NSS/PAM

## 📝 Notas Importantes

### Requisitos
- Arch Linux no host
- KVM/QEMU instalado
- libvirt configurado
- ISO do Arch Linux em `/var/lib/libvirt/images/isos/archlinux.iso`

### Permissões
Todos os scripts devem ser executados como root (sudo).

### Logs
Para ver logs detalhados:
```bash
# Samba
journalctl -xeu samba -f

# dnsmasq
journalctl -xeu dnsmasq -f

# NFS
journalctl -xeu nfs-server -f

# Logs do dnsmasq (DHCP/TFTP)
tail -f /var/log/dnsmasq.log
```

### Troubleshooting
Se algo falhar:
1. Execute o script de diagnóstico: `sudo scripts/monitoring/ragos-diagnostic.sh`
2. Verifique os logs (comandos acima)
3. Consulte a documentação em `docs/`

## 🔄 Estado Atual do Projeto

### ✅ Implementado
- [x] Phase 0: Scripts de limpeza e storage
- [x] Phase 1: Scripts de criação de rede e VMs
- [x] Phase 3: Script de configuração do AD
- [x] Ferramentas de monitoramento
- [x] Scripts de adesão ao domínio

### 🚧 Em Desenvolvimento
- [ ] Phase 2: Scripts de instalação automatizada do Arch
- [ ] Phase 3: Scripts de NFS, rede e PXE
- [ ] Phase 4: Scripts de criação da Golden Image
- [ ] Phase 5: Scripts de configuração do boot PXE
- [ ] Script mestre de instalação completa

## 📚 Documentação Adicional

Para mais informações, consulte:
- [README principal](../README.md)
- [Guia de adesão ao domínio](../docs/domain-join-golden-image.md)
- [Referência rápida](../docs/quick-reference.md)
- [Troubleshooting](../docs/troubleshooting.md)

## 🤝 Contribuir

Para adicionar novos scripts:
1. Siga o padrão de estrutura dos scripts existentes
2. Use cores para output (RED, GREEN, YELLOW, BLUE)
3. Adicione verificações de erro (set -e)
4. Documente no cabeçalho do script
5. Atualize este README

## 📄 Licença

Documentação de código aberto - uso educacional e profissional.

---

**Última atualização:** 2025-11-18  
**Versão:** 1.0
