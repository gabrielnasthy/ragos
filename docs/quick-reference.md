# Guia Rápido: Adesão ao Domínio

## Comando Único (Passo a Passo Manual)

### 1. Entrar no chroot
```bash
# No RAGOS-SERVER
sudo arch-chroot /mnt/ragostorage/nfs_root
```

### 2. Configurar DNS
```bash
cat > /etc/resolv.conf << 'EOF'
search ragos.intra
nameserver 10.0.3.1
EOF
```

### 3. Sincronizar relógio
```bash
pacman -S ntp --noconfirm
sntp -s pool.ntp.org
```

### 4. Criar smb.conf
```bash
mkdir -p /etc/samba
# Copiar o conteúdo de configs/samba/smb.conf.client-example
nano /etc/samba/smb.conf
```

### 5. Criar krb5.conf
```bash
# Copiar o conteúdo de configs/krb5.conf.example
nano /etc/krb5.conf
```

### 6. Aderir ao domínio
```bash
net ads join -U administrator
```

### 7. Verificar
```bash
wbinfo --ping-dc
wbinfo -u
getent passwd administrator@ragos.intra
```

## Comando Único (Script Automatizado)

```bash
# No RAGOS-SERVER
sudo arch-chroot /mnt/ragostorage/nfs_root

# Dentro do chroot
./prepare-golden-image-for-domain.sh
net ads join -U administrator
./verify-domain-join.sh
```

## Troubleshooting Rápido

### Erro: Preauthentication failed
```bash
# Verificar relógio
date

# Re-sincronizar
sntp -s pool.ntp.org

# Tentar novamente
net ads join -U administrator
```

### Erro: DNS update failed
```bash
# No RAGOS-SERVER (fora do chroot)
sudo samba-tool dns add 127.0.0.1 ragos.intra ragos-client A 10.0.3.100 -U administrator
```

### Erro: Failed to lookup DC info
```bash
# Dentro do chroot
host -t SRV _ldap._tcp.ragos.intra

# Se falhar, verificar /etc/resolv.conf
cat /etc/resolv.conf
```

## Referências

- Documentação completa: `docs/domain-join-golden-image.md`
- Scripts: `scripts/`
- Exemplos de configuração: `configs/`
