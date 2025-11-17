# Aderir a Golden Image ao Domínio Samba AD

## Visão Geral

Este guia detalha o processo de adesão da "Golden Image" (imagem do cliente thin client) ao domínio Samba AD `RAGOS.INTRA`. A Golden Image está localizada em `/mnt/ragostorage/nfs_root` no servidor e será montada via NFS pelos clientes PXE durante o boot.

## Arquitetura e Contexto

### Componentes do Sistema

- **Host (Hipervisor):** Arch Linux com KVM/QEMU e libvirt
- **VM Servidor (RAGOS-SERVER):**
  - Arch Linux
  - Controlador de Domínio Samba AD (domínio: `RAGOS.INTRA`)
  - Servidor NFS (exporta a Golden Image)
  - Servidor DHCP/TFTP (dnsmasq para boot PXE)
  - IP na rede interna: `10.0.3.1`
- **Golden Image:**
  - Localização: `/mnt/ragostorage/nfs_root`
  - SO: Arch Linux + KDE Plasma (SDDM)
  - Estado: Pronta mas ainda não aderiu ao domínio

### Problema Comum

Ao tentar executar `net ads join -U administrator` dentro do chroot da Golden Image, podem surgir erros:

```
Preauthentication failed
The attempted logon is invalid
```

**Causa Raiz:** Mesmo que o `kinit administrator@RAGOS.INTRA` funcione, o `net ads join` falha devido a:

1. **Dessincronização de relógio:** O Kerberos é extremamente sensível ao tempo. O chroot não tem acesso direto ao relógio do sistema.
2. **Falta de configuração Samba:** O chroot precisa de um `/etc/samba/smb.conf` mínimo que defina o realm e workgroup.
3. **DNS não configurado:** O chroot pode não ter acesso correto ao DNS do domínio.

## Pré-requisitos

Antes de começar, **confirme no RAGOS-SERVER** que:

### 1. O Servidor AD está funcional

```bash
# Na sua sessão SSH (no RAGOS-SERVER)
sudo systemctl status samba
```

**Resultado esperado:** `active (running)`

```bash
# Verificar o nível funcional do domínio
sudo samba-tool domain level show
```

### 2. O DNS está a resolver corretamente

```bash
# Na sua sessão SSH (no RAGOS-SERVER)
host -t A ragos-server.ragos.intra
host -t A ragos.intra
```

**Resultado esperado:** Ambos devem retornar `10.0.3.1`

### 3. A Golden Image está montada

```bash
# Na sua sessão SSH (no RAGOS-SERVER)
ls -la /mnt/ragostorage/nfs_root
```

**Resultado esperado:** Deve ver uma árvore de diretórios do sistema Arch Linux (`/bin`, `/etc`, `/usr`, etc.)

## Procedimento: Aderir ao Domínio (Dentro do Chroot)

### Passo 1: Entrar no Ambiente Chroot

**Onde:** Na sua sessão SSH (no RAGOS-SERVER)

```bash
sudo arch-chroot /mnt/ragostorage/nfs_root
```

Agora você está **dentro do chroot**. Todos os comandos seguintes são executados aqui.

---

### Passo 2: Configurar o DNS

**Porquê:** O chroot precisa de resolver os registros DNS do domínio (`RAGOS.INTRA`, `_ldap._tcp.ragos.intra`, etc.) para que o Kerberos e o Samba funcionem.

**Como:** Criar o ficheiro `/etc/resolv.conf` apontando para o servidor AD:

```bash
# Dentro do chroot
cat > /etc/resolv.conf << 'EOF'
search ragos.intra
nameserver 10.0.3.1
EOF
```

**Verificar:**

```bash
# Dentro do chroot
cat /etc/resolv.conf
```

**Resultado esperado:**

```
search ragos.intra
nameserver 10.0.3.1
```

**Testar resolução DNS:**

```bash
# Dentro do chroot
host -t A ragos.intra
host -t SRV _ldap._tcp.ragos.intra
```

**Resultado esperado:**
- `ragos.intra has address 10.0.3.1`
- Registro SRV apontando para `ragos-server.ragos.intra`

---

### Passo 3: Sincronizar o Relógio

**Porquê:** O Kerberos rejeita tickets se a diferença de tempo entre o cliente e o servidor AD for superior a 5 minutos. O chroot não tem acesso automático ao relógio do sistema.

**Como:**

#### 3.1. Instalar o pacote NTP

```bash
# Dentro do chroot
pacman -S ntp --noconfirm
```

**Verificar:**

```bash
# Dentro do chroot
which sntp
```

**Resultado esperado:** `/usr/bin/sntp`

#### 3.2. Sincronizar com um servidor NTP público

```bash
# Dentro do chroot
sntp -s pool.ntp.org
```

**Nota:** Se não houver acesso à Internet a partir do chroot, use o IP do servidor AD (que deve ter NTP configurado):

```bash
# Dentro do chroot (alternativa sem Internet)
sntp -s 10.0.3.1
```

**Verificar:**

```bash
# Dentro do chroot
date
```

Compare a saída com o relógio do servidor:

```bash
# Em outra sessão SSH (no RAGOS-SERVER, FORA do chroot)
date
```

**Resultado esperado:** A diferença deve ser inferior a 5 segundos.

---

### Passo 4: Criar o Ficheiro de Configuração do Samba

**Porquê:** O comando `net ads join` precisa de saber o realm Kerberos e o workgroup NetBIOS do domínio. Sem o `smb.conf`, ele não consegue localizar o controlador de domínio.

**Como:** Criar o ficheiro `/etc/samba/smb.conf` dentro do chroot:

```bash
# Dentro do chroot
mkdir -p /etc/samba
cat > /etc/samba/smb.conf << 'EOF'
[global]
    # Identificação do Domínio
    workgroup = RAGOS
    realm = RAGOS.INTRA
    security = ADS

    # Servidor de Autenticação
    password server = ragos-server.ragos.intra

    # Kerberos
    kerberos method = secrets and keytab
    dedicated keytab file = /etc/krb5.keytab

    # DNS e Resolução de Nomes
    name resolve order = host wins bcast

    # ID Mapping (configuração básica)
    idmap config * : backend = tdb
    idmap config * : range = 3000000-3999999
    
    idmap config RAGOS : backend = rid
    idmap config RAGOS : range = 10000-999999

    # Mapeamento de Utilizadores
    template shell = /bin/bash
    template homedir = /home/%U

    # Logs
    log level = 1
    log file = /var/log/samba/log.%m
    max log size = 50

    # Modo Cliente (não é servidor de ficheiros)
    server role = member server
EOF
```

**Explicação dos Parâmetros Principais:**

- **`workgroup`:** Nome NetBIOS do domínio (primeiros 15 caracteres do realm, sem o TLD).
- **`realm`:** Nome completo do domínio Kerberos (em MAIÚSCULAS).
- **`security = ADS`:** Indica que o cliente usará Active Directory para autenticação.
- **`password server`:** FQDN do controlador de domínio.
- **`idmap config`:** Mapeia os SIDs do Windows para UIDs/GIDs do Linux. O backend `rid` é simples e eficiente para domínios pequenos.
- **`template shell` e `template homedir`:** Definem o shell e a home padrão para utilizadores do domínio.

**Verificar:**

```bash
# Dentro do chroot
cat /etc/samba/smb.conf
testparm -s
```

**Resultado esperado:** O `testparm` deve processar o ficheiro sem erros e exibir a configuração.

---

### Passo 5: Configurar o Kerberos

**Porquê:** O Samba usa o Kerberos para autenticação no AD. O ficheiro `/etc/krb5.conf` define como o cliente localiza os KDCs (Key Distribution Centers) do domínio.

**Como:** Criar o ficheiro `/etc/krb5.conf` dentro do chroot:

```bash
# Dentro do chroot
cat > /etc/krb5.conf << 'EOF'
[libdefaults]
    default_realm = RAGOS.INTRA
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    RAGOS.INTRA = {
        kdc = ragos-server.ragos.intra
        admin_server = ragos-server.ragos.intra
        default_domain = ragos.intra
    }

[domain_realm]
    .ragos.intra = RAGOS.INTRA
    ragos.intra = RAGOS.INTRA

[logging]
    default = FILE:/var/log/krb5libs.log
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmind.log
EOF
```

**Explicação dos Parâmetros Principais:**

- **`default_realm`:** Realm Kerberos padrão (deve corresponder ao `realm` do `smb.conf`).
- **`dns_lookup_kdc`:** Permite descobrir KDCs através de registros SRV do DNS.
- **`kdc` e `admin_server`:** FQDN do controlador de domínio.
- **`[domain_realm]`:** Mapeia domínios DNS para realms Kerberos.

**Verificar:**

```bash
# Dentro do chroot
cat /etc/krb5.conf
```

**Testar Kerberos:**

```bash
# Dentro do chroot
kinit administrator@RAGOS.INTRA
```

**Resultado esperado:** Solicitará a password do administrador. Se bem-sucedido, prossiga:

```bash
# Dentro do chroot
klist
```

**Resultado esperado:**

```
Ticket cache: KEYRING:persistent:0:0
Default principal: administrator@RAGOS.INTRA

Valid starting     Expires            Service principal
...                ...                krbtgt/RAGOS.INTRA@RAGOS.INTRA
```

Se o `klist` mostrar um ticket válido, o Kerberos está funcional. **Destrua o ticket antes de prosseguir:**

```bash
# Dentro do chroot
kdestroy
```

---

### Passo 6: Aderir ao Domínio

**Porquê:** Agora que o DNS, relógio e configuração Samba/Kerberos estão corretos, podemos executar o `net ads join`.

**Como:**

```bash
# Dentro do chroot
net ads join -U administrator
```

**Resultado esperado:**

1. Solicitará a password do `administrator`.
2. Após inserir a password, deve exibir:

```
Using short domain name -- RAGOS
Joined 'RAGOS-CLIENT' to dns domain 'ragos.intra'
```

**Em caso de erro:**

Se surgir `Preauthentication failed` novamente:

1. **Verifique o relógio:**

   ```bash
   # Dentro do chroot
   date
   ```

   Compare com o servidor (fora do chroot). Diferença máxima permitida: 5 minutos.

2. **Verifique o DNS:**

   ```bash
   # Dentro do chroot
   host -t SRV _kerberos._tcp.ragos.intra
   ```

   Deve retornar um registro SRV apontando para `ragos-server.ragos.intra`.

3. **Verifique os logs do Samba:**

   ```bash
   # Dentro do chroot
   tail -n 50 /var/log/samba/log.net
   ```

4. **Verifique os logs do Kerberos:**

   ```bash
   # Dentro do chroot
   tail -n 50 /var/log/krb5libs.log
   ```

---

### Passo 7: Verificar a Adesão ao Domínio

**Porquê:** Após o `net ads join`, devemos confirmar que:
1. O computador foi criado no AD.
2. O keytab foi gerado corretamente.
3. O sistema consegue autenticar utilizadores do domínio.

#### 7.1. Verificar o Objeto do Computador no AD

**Onde:** Em outra sessão SSH (no RAGOS-SERVER, **FORA** do chroot)

```bash
# Fora do chroot (no RAGOS-SERVER)
sudo samba-tool computer list
```

**Resultado esperado:** Deve aparecer o nome do computador que aderiu (ex: `RAGOS-CLIENT$`).

#### 7.2. Verificar o Keytab

**Onde:** Dentro do chroot

```bash
# Dentro do chroot
ls -l /etc/krb5.keytab
```

**Resultado esperado:** O ficheiro deve existir e ter permissões `600` (legível apenas pelo root).

```bash
# Dentro do chroot
klist -k /etc/krb5.keytab
```

**Resultado esperado:** Deve listar vários principals, incluindo:

```
Keytab name: FILE:/etc/krb5.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   1 RAGOS-CLIENT$@RAGOS.INTRA
   1 host/ragos-client.ragos.intra@RAGOS.INTRA
   ...
```

#### 7.3. Testar Autenticação de Utilizadores do Domínio

**Onde:** Dentro do chroot

```bash
# Dentro do chroot
wbinfo --ping-dc
```

**Resultado esperado:** `checking the NETLOGON for domain[RAGOS] dc connection to "ragos-server.ragos.intra" succeeded`

```bash
# Dentro do chroot
wbinfo -u
```

**Resultado esperado:** Lista de utilizadores do domínio (ex: `RAGOS\administrator`, `RAGOS\user1`).

```bash
# Dentro do chroot
wbinfo -g
```

**Resultado esperado:** Lista de grupos do domínio (ex: `RAGOS\domain admins`, `RAGOS\domain users`).

**Testar resolução de nomes:**

```bash
# Dentro do chroot
getent passwd administrator@ragos.intra
```

**Resultado esperado:** Deve exibir uma entrada do tipo:

```
administrator@ragos.intra:*:10500:10513::/home/administrator@ragos.intra:/bin/bash
```

Se **todos estes testes passarem**, a Golden Image aderiu com sucesso ao domínio!

---

### Passo 8: Configurar o SSSD (Opcional mas Recomendado)

**Porquê:** O SSSD (System Security Services Daemon) oferece cache local de credenciais, melhor performance e integração com PAM/NSS. É a solução recomendada para clientes Linux em domínios AD.

**Como:** Instalar e configurar o SSSD dentro do chroot.

#### 8.1. Instalar o SSSD

```bash
# Dentro do chroot
pacman -S sssd --noconfirm
```

#### 8.2. Criar o Ficheiro de Configuração

```bash
# Dentro do chroot
cat > /etc/sssd/sssd.conf << 'EOF'
[sssd]
services = nss, pam
config_file_version = 2
domains = ragos.intra

[nss]
filter_users = root
filter_groups = root

[pam]

[domain/ragos.intra]
id_provider = ad
auth_provider = ad
access_provider = ad
chpass_provider = ad

ad_domain = ragos.intra
ad_server = ragos-server.ragos.intra

ldap_id_mapping = True
ldap_schema = ad

cache_credentials = True
krb5_store_password_if_offline = True

fallback_homedir = /home/%u@%d
default_shell = /bin/bash

use_fully_qualified_names = True
EOF
```

#### 8.3. Definir Permissões Corretas

```bash
# Dentro do chroot
chmod 600 /etc/sssd/sssd.conf
chown root:root /etc/sssd/sssd.conf
```

#### 8.4. Habilitar o SSSD para Iniciar no Boot

**Nota:** Dentro do chroot, não podemos iniciar serviços diretamente. Apenas habilitamos:

```bash
# Dentro do chroot
systemctl enable sssd
```

#### 8.5. Configurar PAM e NSS

**Editar `/etc/nsswitch.conf`:**

```bash
# Dentro do chroot
cp /etc/nsswitch.conf /etc/nsswitch.conf.backup

cat > /etc/nsswitch.conf << 'EOF'
passwd: files sss
shadow: files sss
group: files sss

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

netgroup: files sss
automount: files sss
EOF
```

**Configurar PAM:** Instalar o `pam_sss`:

```bash
# Dentro do chroot
# (O pacote sssd já inclui o módulo pam_sss)
```

**Editar `/etc/pam.d/system-auth`:**

```bash
# Dentro do chroot
cat > /etc/pam.d/system-auth << 'EOF'
#%PAM-1.0

auth       required                    pam_env.so
auth       required                    pam_faildelay.so delay=2000000
auth       sufficient                  pam_unix.so try_first_pass nullok
auth       sufficient                  pam_sss.so use_first_pass
auth       required                    pam_deny.so

account    required                    pam_unix.so
account    sufficient                  pam_localuser.so
account    sufficient                  pam_succeed_if.so uid < 1000 quiet
account    [default=bad success=ok user_unknown=ignore] pam_sss.so
account    required                    pam_permit.so

password   required                    pam_pwquality.so retry=3
password   sufficient                  pam_unix.so sha512 shadow try_first_pass
password   sufficient                  pam_sss.so use_authtok
password   required                    pam_deny.so

session    optional                    pam_keyinit.so revoke
session    required                    pam_limits.so
-session   optional                    pam_systemd.so
session    required                    pam_unix.so
session    optional                    pam_sss.so
session    optional                    pam_mkhomedir.so umask=0077
EOF
```

**Verificar:**

```bash
# Dentro do chroot
cat /etc/pam.d/system-auth
```

**Nota:** Quando o cliente thin client arrancar via NFS, o SSSD iniciará automaticamente e os utilizadores do domínio poderão fazer login através do SDDM.

---

### Passo 9: Sair do Chroot

```bash
# Dentro do chroot
exit
```

Agora você está de volta ao RAGOS-SERVER.

---

## Verificação Final (Fora do Chroot)

### 1. Confirmar o Objeto no AD

```bash
# No RAGOS-SERVER (fora do chroot)
sudo samba-tool computer show 'RAGOS-CLIENT$'
```

**Resultado esperado:** Exibe os atributos do objeto do computador no AD.

### 2. Testar Boot PXE

Inicie um cliente thin client via PXE. O cliente deve:

1. Obter IP via DHCP do `dnsmasq`.
2. Baixar o bootloader GRUB via TFTP.
3. Montar o NFS root (`10.0.3.1:/nfs_root`).
4. Carregar o Arch Linux + KDE.
5. Exibir o SDDM com opção de login no domínio (`RAGOS\utilizador` ou `utilizador@ragos.intra`).

---

## Troubleshooting Comum

### Erro: `DNS update failed: NT_STATUS_INVALID_PARAMETER`

**Causa:** O servidor DNS (Samba) não permite atualizações dinâmicas.

**Solução:** Adicione manualmente o registro A do cliente no DNS:

```bash
# No RAGOS-SERVER (fora do chroot)
sudo samba-tool dns add 127.0.0.1 ragos.intra ragos-client A 10.0.3.100 -U administrator
```

### Erro: `Failed to join domain: failed to lookup DC info`

**Causa:** O DNS não está a resolver corretamente.

**Solução:**

1. Verifique `/etc/resolv.conf` dentro do chroot.
2. Teste `host -t SRV _ldap._tcp.ragos.intra` dentro do chroot.

### Erro: `Clock skew too great`

**Causa:** Diferença de tempo entre o cliente e o servidor AD superior a 5 minutos.

**Solução:** Sincronize o relógio:

```bash
# Dentro do chroot
sntp -s pool.ntp.org
```

### Winbind não consegue listar utilizadores

**Causa:** O serviço `winbind` não está a correr ou o `smb.conf` está mal configurado.

**Solução:**

1. **Dentro do chroot (não podemos iniciar serviços, mas habilitamos):**

   ```bash
   systemctl enable winbind
   ```

2. **Após o boot do cliente PXE, SSH para ele e inicie:**

   ```bash
   sudo systemctl start winbind
   sudo wbinfo -u
   ```

### SSSD não está a funcionar

**Causa:** Permissões do `/etc/sssd/sssd.conf` incorretas ou configuração inválida.

**Solução:**

```bash
# Dentro do chroot
chmod 600 /etc/sssd/sssd.conf
sssctl config-check
```

---

## Scripts Auxiliares

Para automatizar este processo, consulte os scripts em `/scripts/`:

- **`prepare-golden-image-for-domain.sh`:** Script completo que executa todos os passos 2-6 automaticamente.
- **`verify-domain-join.sh`:** Script de verificação que testa a adesão ao domínio.

---

## Referências

- [Samba Wiki: Setting up Samba as a Domain Member](https://wiki.samba.org/index.php/Setting_up_Samba_as_a_Domain_Member)
- [Arch Linux Wiki: Active Directory Integration](https://wiki.archlinux.org/title/Active_Directory_integration)
- [SSSD Documentation](https://sssd.io/)
- [Kerberos Documentation](https://web.mit.edu/kerberos/krb5-latest/doc/)

---

## Conclusão

Seguindo este guia, a Golden Image do RAGOSthinclient deve aderir com sucesso ao domínio `RAGOS.INTRA`. Os clientes thin client que arrancarem via PXE e montarem esta imagem via NFS poderão autenticar utilizadores do domínio através do SDDM/SSSD.

**Próximos Passos:**

1. Testar o login de utilizadores do domínio no cliente PXE.
2. Configurar perfis móveis (roaming profiles) ou redirecionamento de pastas.
3. Aplicar GPOs (Group Policy Objects) se necessário.

---

**Autor:** RAGOS Agent  
**Data:** 2025-11-17  
**Versão:** 1.0
