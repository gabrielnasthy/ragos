# Troubleshooting: Adesão ao Domínio

Este guia detalha os problemas mais comuns ao aderir a Golden Image ao domínio Samba AD e como resolvê-los.

## Índice

- [Erro: Preauthentication failed](#erro-preauthentication-failed)
- [Erro: Failed to lookup DC info](#erro-failed-to-lookup-dc-info)
- [Erro: DNS update failed](#erro-dns-update-failed)
- [Erro: Clock skew too great](#erro-clock-skew-too-great)
- [Erro: The attempted logon is invalid](#erro-the-attempted-logon-is-invalid)
- [Winbind não lista utilizadores](#winbind-não-lista-utilizadores)
- [SSSD não está a funcionar](#sssd-não-está-a-funcionar)
- [getent não resolve utilizadores do domínio](#getent-não-resolve-utilizadores-do-domínio)
- [Cliente PXE não arranca](#cliente-pxe-não-arranca)
- [Logs úteis](#logs-úteis)

---

## Erro: Preauthentication failed

### Sintoma

```
Failed to join domain: failed to precreate account in ou ou=computers,dc=ragos,dc=intra: Preauthentication failed
```

### Causa

1. **Relógio dessincronizado** - A causa mais comum. O Kerberos rejeita tickets se a diferença de tempo for superior a 5 minutos.
2. **Password incorreta** - A password do administrator está errada.
3. **DNS não está a resolver** - O cliente não consegue encontrar o KDC.

### Solução

#### 1. Verificar sincronização de relógio

**Dentro do chroot:**

```bash
date
```

**Fora do chroot (no RAGOS-SERVER):**

```bash
date
```

Compare as duas saídas. Se a diferença for superior a 5 minutos, sincronize:

**Dentro do chroot:**

```bash
sntp -s pool.ntp.org
# OU (se não houver Internet)
sntp -s 10.0.3.1
```

Verifique novamente:

```bash
date
```

#### 2. Verificar password do administrator

Teste a autenticação Kerberos:

```bash
# Dentro do chroot
kinit administrator@RAGOS.INTRA
```

Se falhar, a password está incorreta. Corrija no servidor:

```bash
# Fora do chroot (no RAGOS-SERVER)
sudo samba-tool user setpassword administrator
```

#### 3. Verificar DNS

```bash
# Dentro do chroot
host -t A ragos.intra
host -t SRV _kerberos._tcp.ragos.intra
```

Se falhar, verifique `/etc/resolv.conf`:

```bash
cat /etc/resolv.conf
```

Deve conter:

```
search ragos.intra
nameserver 10.0.3.1
```

---

## Erro: Failed to lookup DC info

### Sintoma

```
Failed to join domain: failed to lookup DC info for domain 'RAGOS.INTRA' over rpc: NT_STATUS_INVALID_PARAMETER
```

### Causa

O DNS não está a resolver os registros SRV do domínio.

### Solução

#### 1. Verificar resolv.conf

**Dentro do chroot:**

```bash
cat /etc/resolv.conf
```

Deve apontar para o servidor AD:

```
search ragos.intra
nameserver 10.0.3.1
```

Se estiver incorreto, corrija:

```bash
cat > /etc/resolv.conf << 'EOF'
search ragos.intra
nameserver 10.0.3.1
EOF
```

#### 2. Testar resolução DNS

```bash
# Dentro do chroot
host -t A ragos.intra
host -t A ragos-server.ragos.intra
host -t SRV _ldap._tcp.ragos.intra
host -t SRV _kerberos._tcp.ragos.intra
```

**Resultado esperado:**

```
ragos.intra has address 10.0.3.1
ragos-server.ragos.intra has address 10.0.3.1
_ldap._tcp.ragos.intra has SRV record ...
_kerberos._tcp.ragos.intra has SRV record ...
```

#### 3. Verificar servidor DNS do Samba

**Fora do chroot (no RAGOS-SERVER):**

```bash
sudo systemctl status samba
sudo samba-tool dns query 127.0.0.1 ragos.intra @ ALL -U administrator
```

---

## Erro: DNS update failed

### Sintoma

```
Joined 'RAGOS-CLIENT' to dns domain 'ragos.intra'
DNS update failed: NT_STATUS_INVALID_PARAMETER
```

### Causa

O servidor DNS (Samba) está configurado para não aceitar atualizações dinâmicas seguras do cliente.

### Solução

**Nota:** Este erro não impede a adesão ao domínio. O objeto do computador foi criado no AD, mas o registro DNS A não foi atualizado automaticamente.

#### 1. Verificar se o computador aderiu

**Fora do chroot (no RAGOS-SERVER):**

```bash
sudo samba-tool computer list
```

Deve aparecer o nome do computador (ex: `RAGOS-CLIENT$`).

#### 2. Adicionar registro DNS manualmente

**Fora do chroot (no RAGOS-SERVER):**

```bash
sudo samba-tool dns add 127.0.0.1 ragos.intra ragos-client A 10.0.3.100 -U administrator
```

**Nota:** Substitua `ragos-client` pelo nome do computador e `10.0.3.100` pelo IP que será atribuído pelo DHCP.

#### 3. Verificar registro DNS

```bash
# Fora do chroot
sudo samba-tool dns query 127.0.0.1 ragos.intra ragos-client A -U administrator
```

---

## Erro: Clock skew too great

### Sintoma

```
kinit: Clock skew too great while getting initial credentials
```

### Causa

A diferença de tempo entre o cliente e o servidor AD é superior a 5 minutos.

### Solução

**Dentro do chroot:**

```bash
# Sincronizar com servidor NTP público
sntp -s pool.ntp.org

# OU sincronizar com o servidor AD
sntp -s 10.0.3.1

# Verificar
date
```

**Dica:** Para evitar este problema, configure o NTP permanentemente:

```bash
# Dentro do chroot
systemctl enable systemd-timesyncd
cat > /etc/systemd/timesyncd.conf << 'EOF'
[Time]
NTP=pool.ntp.org
FallbackNTP=10.0.3.1
EOF
```

---

## Erro: The attempted logon is invalid

### Sintoma

```
Failed to join domain: failed to precreate account: The attempted logon is invalid.
```

### Causa

1. **Password incorreta** do administrator.
2. **Conta bloqueada** no AD.
3. **Realm incorreto** no krb5.conf ou smb.conf.

### Solução

#### 1. Verificar password

```bash
# Dentro do chroot
kinit administrator@RAGOS.INTRA
```

Se pedir password mas depois falhar, a conta pode estar bloqueada.

#### 2. Verificar estado da conta

**Fora do chroot (no RAGOS-SERVER):**

```bash
sudo samba-tool user show administrator
```

Verifique o campo `accountExpires` e se a conta está ativa.

#### 3. Desbloquear conta (se necessário)

```bash
# Fora do chroot
sudo samba-tool user unlock administrator
```

#### 4. Verificar realm/workgroup

**Dentro do chroot:**

```bash
grep -i realm /etc/krb5.conf
grep -i realm /etc/samba/smb.conf
grep -i workgroup /etc/samba/smb.conf
```

Todos devem estar consistentes:

- `realm = RAGOS.INTRA` (em MAIÚSCULAS)
- `workgroup = RAGOS`

---

## Winbind não lista utilizadores

### Sintoma

```bash
wbinfo -u
# (sem output ou erro)
```

### Causa

1. **Serviço winbind não está a correr**
2. **Configuração do smb.conf incorreta**
3. **Keytab não existe ou está corrompido**

### Solução

#### 1. Verificar serviço

```bash
systemctl status winbind
```

Se não estiver ativo:

```bash
systemctl start winbind
systemctl enable winbind
```

#### 2. Testar conectividade com o DC

```bash
wbinfo --ping-dc
```

**Resultado esperado:**

```
checking the NETLOGON for domain[RAGOS] dc connection to "ragos-server.ragos.intra" succeeded
```

#### 3. Verificar keytab

```bash
ls -l /etc/krb5.keytab
klist -k /etc/krb5.keytab
```

Se o keytab não existir ou estiver vazio, re-adira ao domínio:

```bash
net ads leave -U administrator
net ads join -U administrator
```

#### 4. Verificar logs

```bash
tail -f /var/log/samba/log.winbindd
```

---

## SSSD não está a funcionar

### Sintoma

```bash
systemctl status sssd
# (falhou ou não inicia)
```

### Causa

1. **Permissões do sssd.conf incorretas**
2. **Configuração inválida**
3. **Serviços dependentes não estão a correr**

### Solução

#### 1. Verificar permissões

```bash
ls -l /etc/sssd/sssd.conf
```

Deve ser `600` e pertencer ao root:

```bash
chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
```

#### 2. Verificar configuração

```bash
sssctl config-check
```

Se houver erros, corrija o `/etc/sssd/sssd.conf`.

#### 3. Limpar cache e reiniciar

```bash
systemctl stop sssd
rm -rf /var/lib/sss/db/*
systemctl start sssd
```

#### 4. Verificar logs

```bash
tail -f /var/log/sssd/sssd_ragos.intra.log
```

---

## getent não resolve utilizadores do domínio

### Sintoma

```bash
getent passwd administrator@ragos.intra
# (sem output)
```

### Causa

1. **NSS não está configurado**
2. **Winbind/SSSD não estão a correr**
3. **Cache corrompido**

### Solução

#### 1. Verificar nsswitch.conf

```bash
cat /etc/nsswitch.conf
```

As linhas `passwd`, `group` e `shadow` devem incluir `sss` ou `winbind`:

```
passwd: files sss
group: files sss
shadow: files sss
```

OU (se usar Winbind):

```
passwd: files winbind
group: files winbind
```

#### 2. Verificar serviços

```bash
systemctl status sssd
# OU
systemctl status winbind
```

#### 3. Testar diretamente

**Com SSSD:**

```bash
getent -s sss passwd administrator@ragos.intra
```

**Com Winbind:**

```bash
wbinfo -i administrator@ragos.intra
```

Se funcionar, o problema está no `nsswitch.conf`.

---

## Cliente PXE não arranca

### Sintoma

O cliente thin client não consegue arrancar via PXE ou falha ao montar o NFS.

### Causa

1. **DHCP não está a responder**
2. **TFTP não está acessível**
3. **NFS não está exportado corretamente**
4. **Firewall está a bloquear**

### Solução

#### 1. Verificar DHCP (no RAGOS-SERVER)

```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -f
```

Testar DHCP:

```bash
sudo nmap --script broadcast-dhcp-discover -e enp2s0
```

#### 2. Verificar TFTP

```bash
# No RAGOS-SERVER
sudo systemctl status dnsmasq

# Testar TFTP localmente
curl tftp://10.0.3.1/grub/grub.cfg
```

#### 3. Verificar NFS

```bash
# No RAGOS-SERVER
sudo exportfs -v
sudo showmount -e 10.0.3.1
```

Deve mostrar:

```
/mnt/ragostorage/nfs_root 10.0.3.0/24
```

#### 4. Verificar firewall

```bash
# No RAGOS-SERVER
sudo firewall-cmd --list-all --zone=internal
```

Deve permitir:

- dhcp
- tftp
- nfs
- rpc-bind
- mountd

Se faltar algum serviço:

```bash
sudo firewall-cmd --zone=internal --add-service=dhcp --permanent
sudo firewall-cmd --zone=internal --add-service=tftp --permanent
sudo firewall-cmd --zone=internal --add-service=nfs --permanent
sudo firewall-cmd --zone=internal --add-service=rpc-bind --permanent
sudo firewall-cmd --zone=internal --add-service=mountd --permanent
sudo firewall-cmd --reload
```

---

## Logs Úteis

### Samba/Winbind

```bash
# Log geral do Samba
tail -f /var/log/samba/log.smbd

# Log do Winbind
tail -f /var/log/samba/log.winbindd

# Log do net ads join
tail -f /var/log/samba/log.net
```

### Kerberos

```bash
# Log das bibliotecas Kerberos
tail -f /var/log/krb5libs.log
```

### SSSD

```bash
# Log do domínio
tail -f /var/log/sssd/sssd_ragos.intra.log

# Log geral
tail -f /var/log/sssd/sssd.log
```

### systemd

```bash
# Logs do Samba
journalctl -u samba -f

# Logs do Winbind
journalctl -u winbind -f

# Logs do SSSD
journalctl -u sssd -f

# Logs do dnsmasq
journalctl -u dnsmasq -f

# Logs do NFS
journalctl -u nfs-server -f
```

### Aumentar verbosidade dos logs

#### Samba (temporário)

```bash
# Dentro do chroot ou no cliente
net ads join -U administrator -d 10
```

#### SSSD (permanente)

Editar `/etc/sssd/sssd.conf`:

```ini
[domain/ragos.intra]
debug_level = 9
```

Reiniciar:

```bash
systemctl restart sssd
```

---

## Comandos de Diagnóstico

### Resumo Rápido

```bash
# DNS
host -t A ragos.intra
host -t SRV _ldap._tcp.ragos.intra

# Kerberos
kinit administrator@RAGOS.INTRA
klist

# Samba
testparm -s
net ads testjoin
net ads info

# Winbind
wbinfo --ping-dc
wbinfo -u
wbinfo -g

# NSS
getent passwd administrator@ragos.intra
getent group "domain users@ragos.intra"

# SSSD
sssctl config-check
sssctl domain-status ragos.intra

# NFS
showmount -e 10.0.3.1

# Firewall
firewall-cmd --list-all --zone=internal

# Relógio
date
timedatectl status
```

---

## Referências

- [Samba Wiki: Troubleshooting](https://wiki.samba.org/index.php/Troubleshooting_Samba_Domain_Members)
- [Arch Wiki: Samba](https://wiki.archlinux.org/title/Samba)
- [Arch Wiki: Active Directory Integration](https://wiki.archlinux.org/title/Active_Directory_integration)
- [SSSD Troubleshooting](https://sssd.io/troubleshooting/basics.html)

---

**Última atualização:** 2025-11-17  
**Versão:** 1.0
