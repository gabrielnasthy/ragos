# Changelog

Todas as mudanças notáveis neste projeto serão documentadas neste ficheiro.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/pt-PT/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-PT/).

## [1.0.0] - 2025-11-17

### Adicionado

#### Documentação
- Guia completo de adesão ao domínio (`docs/domain-join-golden-image.md`)
  - 760 linhas de documentação detalhada
  - Explicação da arquitetura do sistema
  - Procedimento passo a passo (8 passos)
  - Verificações e troubleshooting
- Guia rápido de referência (`docs/quick-reference.md`)
  - Comandos essenciais
  - Troubleshooting rápido
  - Referências
- Guia de troubleshooting completo (`docs/troubleshooting.md`)
  - 712 linhas cobrindo 10+ problemas comuns
  - Sintomas, causas e soluções detalhadas
  - Logs úteis e comandos de diagnóstico
- Índice de navegação (`docs/INDEX.md`)
  - Guia de navegação da documentação
  - Fluxo de aprendizagem recomendado
  - Organização por objetivos

#### Scripts
- Script de preparação da Golden Image (`scripts/prepare-golden-image-for-domain.sh`)
  - 284 linhas de código bash
  - Automatiza toda a preparação do chroot
  - Verificações de pré-requisitos
  - Output colorido e informativo
  - Validações em cada passo
- Script de verificação de adesão (`scripts/verify-domain-join.sh`)
  - 264 linhas de código bash
  - 8 testes automatizados
  - Relatório detalhado de status
  - Sugestões de correção

#### Exemplos de Configuração
- `configs/samba/smb.conf.client-example` - Configuração completa do Samba cliente
- `configs/krb5.conf.example` - Configuração completa do Kerberos
- `configs/sssd.conf.example` - Configuração completa do SSSD
- `configs/resolv.conf.example` - Configuração do DNS

#### Outros
- README.md atualizado com:
  - Visão geral da infraestrutura
  - Diagrama de arquitetura ASCII
  - Links para toda a documentação
  - Quick start guide
  - Troubleshooting comum

### Características

#### Documentação
- **Sem omissões de código:** Todos os ficheiros de configuração são fornecidos completos
- **Explicações didáticas:** Cada comando é precedido por uma explicação do "porquê"
- **Verificações incluídas:** Comandos de verificação após cada alteração
- **Localização explícita:** Clara indicação de onde cada comando deve ser executado
- **Sem suposições:** Verificação de pré-requisitos antes de cada passo

#### Scripts
- Validação de ambiente (chroot vs. host)
- Sincronização de relógio com NTP
- Configuração automática de DNS
- Criação de configurações Samba e Kerberos
- Teste de autenticação Kerberos
- Output colorido e informativo
- Tratamento de erros robusto
- Sugestões de troubleshooting integradas

### Resolve

- **Issue principal:** Erro "Preauthentication failed" ao executar `net ads join`
- **Causa 1:** Relógio dessincronizado entre chroot e servidor AD
- **Causa 2:** Falta de ficheiro `/etc/samba/smb.conf` no chroot
- **Causa 3:** DNS não configurado no chroot

### Público-Alvo

Esta release é direcionada para:
- Administradores de sistemas Arch Linux
- Utilizadores implementando thin clients com PXE boot
- Utilizadores integrando Arch Linux com Samba AD
- Estudantes aprendendo sobre infraestrutura Linux enterprise

### Tecnologias Cobertas

- Arch Linux
- KVM/QEMU (libvirt)
- Samba 4 (Active Directory Domain Controller)
- Kerberos (autenticação)
- NFS (network file system)
- PXE Boot (dnsmasq DHCP/TFTP)
- SSSD (System Security Services Daemon)
- Winbind
- PAM/NSS

### Estrutura do Repositório

```
ragos/
├── README.md                           # Visão geral do projeto
├── CHANGELOG.md                        # Este ficheiro
├── docs/
│   ├── INDEX.md                        # Índice de navegação
│   ├── domain-join-golden-image.md    # Guia completo
│   ├── quick-reference.md             # Referência rápida
│   └── troubleshooting.md             # Troubleshooting detalhado
├── scripts/
│   ├── prepare-golden-image-for-domain.sh  # Preparação automatizada
│   └── verify-domain-join.sh              # Verificação automatizada
└── configs/
    ├── krb5.conf.example              # Exemplo Kerberos
    ├── resolv.conf.example            # Exemplo DNS
    ├── sssd.conf.example              # Exemplo SSSD
    └── samba/
        └── smb.conf.client-example    # Exemplo Samba cliente
```

### Estatísticas

- **Total de ficheiros:** 11
- **Total de linhas de documentação:** 1,814
- **Total de linhas de código (scripts):** 548
- **Total de linhas de configuração:** 91
- **Problemas cobertos no troubleshooting:** 10+

### Agradecimentos

Este projeto documenta uma infraestrutura real implementada para resolver desafios práticos na gestão de thin clients Linux em ambientes enterprise com Active Directory.

---

## Formato

### Tipos de Mudanças

- **Adicionado** - para novas funcionalidades
- **Alterado** - para mudanças em funcionalidades existentes
- **Descontinuado** - para funcionalidades que serão removidas
- **Removido** - para funcionalidades removidas
- **Corrigido** - para correções de bugs
- **Segurança** - em caso de vulnerabilidades

---

**Nota:** Este é o primeiro release público do projeto RAGOSthinclient.
