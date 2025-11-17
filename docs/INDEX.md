# Índice da Documentação RAGOSthinclient

Este documento serve como ponto de entrada para toda a documentação do projeto RAGOSthinclient.

## 📖 Para Começar

Se você é novo no projeto, comece por aqui:

1. **[README.md](../README.md)** - Visão geral do projeto, arquitetura e quick start
2. **[Guia Rápido](quick-reference.md)** - Comandos essenciais e referência rápida
3. **[Guia Completo de Adesão ao Domínio](domain-join-golden-image.md)** - Documentação detalhada passo a passo

## 🎯 Por Objetivo

### Quero aderir a Golden Image ao domínio AD

**Opção 1: Script Automatizado (Recomendado)**

```bash
# No RAGOS-SERVER
sudo arch-chroot /mnt/ragostorage/nfs_root

# Dentro do chroot
cd /path/to/ragos
./scripts/prepare-golden-image-for-domain.sh
net ads join -U administrator
./scripts/verify-domain-join.sh
```

**Documentação:** [Guia Completo](domain-join-golden-image.md)

---

**Opção 2: Passo a Passo Manual**

1. Entrar no chroot
2. Configurar DNS
3. Sincronizar relógio
4. Criar smb.conf
5. Criar krb5.conf
6. Executar net ads join

**Documentação:** [Guia Completo - Seção "Procedimento"](domain-join-golden-image.md#procedimento-aderir-ao-domínio-dentro-do-chroot)

---

### Estou com problemas/erros

Consulte o **[Guia de Troubleshooting](troubleshooting.md)** que inclui:

- Preauthentication failed
- Failed to lookup DC info
- DNS update failed
- Clock skew too great
- Winbind não lista utilizadores
- SSSD não funciona
- E muito mais...

---

### Preciso de exemplos de configuração

Todos os exemplos estão em **[configs/](../configs/)**:

- `samba/smb.conf.client-example` - Configuração do Samba cliente
- `krb5.conf.example` - Configuração do Kerberos
- `sssd.conf.example` - Configuração do SSSD
- `resolv.conf.example` - Configuração do DNS

---

### Quero entender a arquitetura do sistema

Consulte:

1. **[README.md - Seção Arquitetura](../README.md#🏗️-arquitetura)**
2. **[Guia Completo - Seção "Arquitetura e Contexto"](domain-join-golden-image.md#arquitetura-e-contexto)**

---

## 🛠️ Scripts Disponíveis

Todos os scripts estão em **[scripts/](../scripts/)**:

### prepare-golden-image-for-domain.sh

**O que faz:**
- Verifica que está dentro do chroot
- Configura DNS
- Sincroniza relógio com NTP
- Cria smb.conf
- Cria krb5.conf
- Testa autenticação Kerberos

**Como usar:**

```bash
# Dentro do chroot
./scripts/prepare-golden-image-for-domain.sh
```

**Documentação:** Cabeçalho do script + [Guia Completo](domain-join-golden-image.md)

---

### verify-domain-join.sh

**O que faz:**
- Verifica existência do keytab
- Testa resolução DNS
- Valida configuração do Samba
- Testa Winbind/SSSD
- Testa NSS/PAM

**Como usar:**

```bash
# Dentro do chroot ou no cliente após boot PXE
./scripts/verify-domain-join.sh
```

**Documentação:** Cabeçalho do script + [Guia Completo - Seção "Verificar a Adesão"](domain-join-golden-image.md#passo-7-verificar-a-adesão-ao-domínio)

---

## 📚 Documentos Completos

### [domain-join-golden-image.md](domain-join-golden-image.md)

**Conteúdo:**
- Visão geral da arquitetura
- Explicação do problema e causa raiz
- Pré-requisitos detalhados
- Procedimento completo passo a passo (8 passos)
- Verificação final
- Troubleshooting comum
- Referências

**Quando usar:** Quando precisar de entender TUDO sobre a adesão ao domínio.

---

### [quick-reference.md](quick-reference.md)

**Conteúdo:**
- Comandos essenciais
- Procedimento resumido (manual e automatizado)
- Troubleshooting rápido (3 erros mais comuns)

**Quando usar:** Quando já souber o processo mas precisar de uma referência rápida.

---

### [troubleshooting.md](troubleshooting.md)

**Conteúdo:**
- 10+ problemas comuns detalhados
- Sintomas, causas e soluções
- Logs úteis
- Comandos de diagnóstico
- Referências externas

**Quando usar:** Quando algo não está a funcionar como esperado.

---

## 🔧 Configurações

### Padrões do Sistema

Os valores padrão usados na documentação e scripts são:

```
DOMAIN_REALM="RAGOS.INTRA"
DOMAIN_WORKGROUP="RAGOS"
DOMAIN_DNS_NAME="ragos.intra"
AD_SERVER_FQDN="ragos-server.ragos.intra"
AD_SERVER_IP="10.0.3.1"
NTP_SERVER="pool.ntp.org"
```

### Como Customizar

Para adaptar à sua infraestrutura:

1. **Scripts:** Edite as variáveis no topo de cada script:
   - `scripts/prepare-golden-image-for-domain.sh` (linhas 26-31)
   - `scripts/verify-domain-join.sh` (linhas 26-29)

2. **Ficheiros de Configuração:** Copie os exemplos e edite:
   ```bash
   cp configs/samba/smb.conf.client-example /mnt/ragostorage/nfs_root/etc/samba/smb.conf
   nano /mnt/ragostorage/nfs_root/etc/samba/smb.conf
   ```

---

## 🎓 Fluxo de Aprendizagem Recomendado

### Iniciante

1. Ler [README.md](../README.md) para visão geral
2. Ler [Guia Rápido](quick-reference.md)
3. Executar scripts automatizados
4. Consultar [Troubleshooting](troubleshooting.md) se necessário

### Intermediário

1. Ler [Guia Completo](domain-join-golden-image.md) seção por seção
2. Executar passo a passo manual
3. Estudar exemplos de configuração em `configs/`
4. Experimentar customizações

### Avançado

1. Estudar scripts linha por linha
2. Entender cada parâmetro de configuração
3. Implementar melhorias (SSSD, GPO, etc.)
4. Contribuir com documentação/scripts

---

## 🤝 Contribuir

Se encontrar erros, tiver sugestões ou quiser contribuir:

1. Abra uma issue no GitHub
2. Faça fork e submeta um PR
3. Melhore a documentação

---

## 📞 Suporte

Se após consultar toda a documentação ainda tiver dúvidas:

1. Verifique se seguiu todos os pré-requisitos
2. Consulte os logs (seção "Logs Úteis" no [Troubleshooting](troubleshooting.md))
3. Abra uma issue com:
   - Descrição do problema
   - Output dos comandos de diagnóstico
   - Logs relevantes

---

**Última atualização:** 2025-11-17  
**Versão:** 1.0
