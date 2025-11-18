#!/bin/bash

###############################################################################
# Script: setup-ad.sh
# Descrição: Configuração completa do Active Directory Samba
# Autor: RAGOS Agent
# Versão: 1.0
# Fase: 3 - Configuração dos Serviços no Servidor
#
# AVISO: Execute este script NO RAGOS-SERVER (via SSH)
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
# Configurações do Domínio
###############################################################################

DOMAIN_REALM="RAGOS.INTRA"
DOMAIN_WORKGROUP="RAGOS"
DOMAIN_DNS="ragos.intra"
ADMIN_PASSWORD="RAG200519@.rocha"
SERVER_IP="10.0.3.1"

print_header "Configuração do Active Directory Samba"

print_info "Configurações do domínio:"
print_info "  Realm: $DOMAIN_REALM"
print_info "  Workgroup: $DOMAIN_WORKGROUP"
print_info "  DNS: $DOMAIN_DNS"
print_info "  IP do servidor: $SERVER_IP"
echo ""

###############################################################################
# Verificar Instalação do Samba
###############################################################################

print_header "Verificando Instalação do Samba"

if ! command -v samba &> /dev/null; then
    print_error "Samba não está instalado"
    print_info "Instalando Samba..."
    pacman -S --noconfirm samba krb5 python-cryptography python-markdown python-dnspython
    print_success "Samba instalado"
else
    print_success "Samba já está instalado"
fi

###############################################################################
# Parar Serviços Conflitantes
###############################################################################

print_header "Parando Serviços Conflitantes"

print_info "Parando systemd-resolved..."
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
print_success "systemd-resolved parado"

# Backup do resolv.conf se for link simbólico
if [ -L /etc/resolv.conf ]; then
    print_info "Removendo link simbólico de /etc/resolv.conf..."
    rm -f /etc/resolv.conf
fi

###############################################################################
# Configurar DNS Estático
###############################################################################

print_header "Configurando DNS Estático"

print_info "Criando /etc/resolv.conf estático..."
cat > /etc/resolv.conf << EOF
search $DOMAIN_DNS
nameserver 127.0.0.1
EOF

print_info "Protegendo /etc/resolv.conf contra alterações..."
chattr +i /etc/resolv.conf
print_success "DNS configurado e protegido"

print_info "Conteúdo do /etc/resolv.conf:"
cat /etc/resolv.conf

###############################################################################
# Configurar Kerberos (Pré-provisionamento)
###############################################################################

print_header "Configurando Kerberos"

print_info "Criando configuração básica do Kerberos..."
cat > /etc/krb5.conf << EOF
[libdefaults]
    default_realm = $DOMAIN_REALM
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    $DOMAIN_REALM = {
        kdc = $SERVER_IP
        admin_server = $SERVER_IP
        default_domain = $DOMAIN_DNS
    }

[domain_realm]
    .$DOMAIN_DNS = $DOMAIN_REALM
    $DOMAIN_DNS = $DOMAIN_REALM
EOF

print_success "Kerberos configurado"

###############################################################################
# Remover Configurações Antigas do Samba
###############################################################################

print_header "Limpando Configurações Antigas"

print_info "Verificando diretórios do Samba..."

if [ -d /var/lib/samba ]; then
    print_warning "Diretório /var/lib/samba existe"
    read -p "Deseja remover configurações antigas? (sim/não): " REMOVE_OLD
    
    if [ "$REMOVE_OLD" == "sim" ]; then
        print_info "Parando Samba (se estiver a correr)..."
        systemctl stop samba 2>/dev/null || true
        
        print_info "Removendo configurações antigas..."
        rm -rf /var/lib/samba/*
        rm -rf /etc/samba/smb.conf 2>/dev/null || true
        
        print_success "Configurações antigas removidas"
    fi
fi

###############################################################################
# Provisionar Domínio
###############################################################################

print_header "Provisionando Domínio Active Directory"

print_info "Executando samba-tool domain provision..."
print_warning "Este processo pode demorar alguns minutos..."
echo ""

samba-tool domain provision \
    --realm="$DOMAIN_REALM" \
    --domain="$DOMAIN_WORKGROUP" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASSWORD" \
    --use-rfc2307 \
    --function-level=2008_R2

print_success "Domínio provisionado"

###############################################################################
# Copiar Configurações Geradas
###############################################################################

print_header "Aplicando Configurações Geradas"

print_info "Copiando krb5.conf gerado..."
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
print_success "Kerberos configurado com arquivo do Samba"

print_info "Copiando smb.conf gerado..."
cp /var/lib/samba/private/smb.conf /etc/samba/smb.conf
print_success "Configuração do Samba aplicada"

###############################################################################
# Otimizar Configuração do Samba
###############################################################################

print_header "Otimizando Configuração do Samba"

print_info "Adicionando configurações de performance..."
cat >> /etc/samba/smb.conf << 'EOF'

# ===================================================================
# Configurações Adicionais RAGOSthinclient
# ===================================================================

[global]
    # Configurações de desempenho
    socket options = TCP_NODELAY SO_RCVBUF=65536 SO_SNDBUF=65536
    use sendfile = true
    aio read size = 1
    aio write size = 1
    
    # Configurações de compatibilidade
    ldap server require strong auth = no
    server min protocol = NT1
    client min protocol = NT1
    
    # Logs otimizados
    log level = 1 auth:2 winbind:2
    max log size = 1000
    
    # DNS dinâmico
    allow dns updates = nonsecure and secure
    
    # Bind interfaces
    interfaces = lo enp2s0
    bind interfaces only = yes
EOF

print_success "Configurações adicionais aplicadas"

###############################################################################
# Iniciar e Habilitar Samba
###############################################################################

print_header "Iniciando Serviço Samba"

print_info "Habilitando Samba para início automático..."
systemctl enable samba
print_success "Samba habilitado"

print_info "Iniciando Samba..."
systemctl start samba
print_success "Samba iniciado"

print_info "Aguardando Samba inicializar completamente..."
sleep 5

print_info "Verificando status do Samba..."
systemctl status samba --no-pager || true

###############################################################################
# Testar Kerberos
###############################################################################

print_header "Testando Autenticação Kerberos"

print_info "Obtendo ticket Kerberos para administrator..."
echo "$ADMIN_PASSWORD" | kinit administrator@"$DOMAIN_REALM"

print_info "Verificando ticket..."
klist

print_success "Kerberos está funcional"

###############################################################################
# Testar DNS
###############################################################################

print_header "Testando DNS Interno"

print_info "Aguardando DNS inicializar..."
sleep 5

print_info "Testando resolução do domínio..."
if host -t A "$DOMAIN_DNS" 127.0.0.1 > /dev/null 2>&1; then
    DNS_RESULT=$(host -t A "$DOMAIN_DNS" 127.0.0.1 | grep "has address" | awk '{print $4}')
    print_success "DNS resolve $DOMAIN_DNS para $DNS_RESULT"
else
    print_warning "DNS ainda não está resolvendo (pode precisar aguardar)"
fi

print_info "Testando registros SRV..."
if host -t SRV "_ldap._tcp.$DOMAIN_DNS" 127.0.0.1 > /dev/null 2>&1; then
    print_success "Registros SRV encontrados"
    host -t SRV "_ldap._tcp.$DOMAIN_DNS" 127.0.0.1
else
    print_warning "Registros SRV ainda não disponíveis (pode precisar aguardar)"
fi

###############################################################################
# Verificar Domínio
###############################################################################

print_header "Verificando Domínio"

print_info "Informações do domínio:"
samba-tool domain info 127.0.0.1

print_info "Nível funcional:"
samba-tool domain level show

print_info "Listando utilizadores:"
samba-tool user list

print_info "Listando grupos:"
samba-tool group list

###############################################################################
# Criar Utilizador de Teste (Opcional)
###############################################################################

print_header "Criando Utilizador de Teste"

read -p "Deseja criar um utilizador de teste? (sim/não): " CREATE_USER

if [ "$CREATE_USER" == "sim" ]; then
    TEST_USER="teste"
    TEST_PASSWORD="Teste123!"
    
    print_info "Criando utilizador: $TEST_USER"
    samba-tool user create "$TEST_USER" "$TEST_PASSWORD" \
        --given-name="Usuario" \
        --surname="Teste" \
        --description="Conta de teste RAGOSthinclient"
    
    print_success "Utilizador $TEST_USER criado"
    print_info "Password: $TEST_PASSWORD"
fi

###############################################################################
# Informações Finais
###############################################################################

print_header "Active Directory Configurado com Sucesso"

print_success "Domínio $DOMAIN_REALM está funcional!"
echo ""
print_info "Detalhes do domínio:"
print_info "  Realm: $DOMAIN_REALM"
print_info "  Workgroup: $DOMAIN_WORKGROUP"
print_info "  DNS: $DOMAIN_DNS"
print_info "  Servidor: $SERVER_IP"
print_info "  Administrator: administrator@$DOMAIN_REALM"
print_info "  Password: $ADMIN_PASSWORD"
echo ""
print_info "Serviço:"
print_info "  Status: $(systemctl is-active samba)"
print_info "  Logs: journalctl -xeu samba"
echo ""
print_info "Testes:"
print_info "  Kerberos: kinit administrator@$DOMAIN_REALM"
print_info "  DNS: host -t A $DOMAIN_DNS"
print_info "  SRV: host -t SRV _ldap._tcp.$DOMAIN_DNS"
print_info "  Domínio: samba-tool domain info 127.0.0.1"
echo ""
print_info "Próximo passo: Configure a rede e firewall"
print_info "Execute: scripts/phase3/setup-network-server.sh"
echo ""

exit 0
