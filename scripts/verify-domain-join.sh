#!/bin/bash

###############################################################################
# Script: verify-domain-join.sh
# Descrição: Verifica se a Golden Image aderiu corretamente ao domínio
# Autor: RAGOS Agent
# Versão: 1.0
# Data: 2025-11-17
#
# AVISO: Este script pode ser executado:
#        1. DENTRO do chroot da Golden Image (verificação prévia ao boot PXE)
#        2. No cliente thin client após boot PXE (verificação em produção)
###############################################################################

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configurações do Domínio (EDITE CONFORME NECESSÁRIO)
DOMAIN_REALM="RAGOS.INTRA"
DOMAIN_WORKGROUP="RAGOS"
DOMAIN_DNS_NAME="ragos.intra"
AD_SERVER_FQDN="ragos-server.ragos.intra"

###############################################################################
# Funções Auxiliares
###############################################################################

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
# Variáveis de Controlo
###############################################################################

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0

###############################################################################
# Testes de Verificação
###############################################################################

print_header "Verificação de Adesão ao Domínio - ${DOMAIN_REALM}"

# Teste 1: Ficheiro krb5.keytab existe
print_info "Teste 1: Verificando keytab..."
if [ -f /etc/krb5.keytab ]; then
    print_success "Ficheiro /etc/krb5.keytab existe"
    
    if [ "$(stat -c %a /etc/krb5.keytab)" == "600" ]; then
        print_success "Permissões do keytab corretas (600)"
    else
        print_warning "Permissões do keytab incorretas: $(stat -c %a /etc/krb5.keytab)"
        print_info "Recomendado: chmod 600 /etc/krb5.keytab"
        TESTS_WARNING=$((TESTS_WARNING + 1))
    fi
    
    print_info "Conteúdo do keytab:"
    klist -k /etc/krb5.keytab | head -n 10
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_error "Ficheiro /etc/krb5.keytab NÃO existe"
    print_info "A máquina não aderiu ao domínio"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Teste 2: DNS está a resolver
print_info "Teste 2: Verificando resolução DNS..."
if host -t A ${DOMAIN_DNS_NAME} > /dev/null 2>&1; then
    DNS_RESULT=$(host -t A ${DOMAIN_DNS_NAME} | grep "has address" | awk '{print $4}')
    print_success "DNS resolve ${DOMAIN_DNS_NAME} para ${DNS_RESULT}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_error "Falha ao resolver ${DOMAIN_DNS_NAME}"
    print_info "Verifique /etc/resolv.conf"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Teste 3: Registros SRV
print_info "Teste 3: Verificando registros SRV..."
if host -t SRV _ldap._tcp.${DOMAIN_DNS_NAME} > /dev/null 2>&1; then
    print_success "Registros SRV encontrados"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_warning "Registros SRV não encontrados"
    TESTS_WARNING=$((TESTS_WARNING + 1))
fi

# Teste 4: Configuração do Samba existe
print_info "Teste 4: Verificando configuração do Samba..."
if [ -f /etc/samba/smb.conf ]; then
    print_success "Ficheiro /etc/samba/smb.conf existe"
    
    if testparm -s /etc/samba/smb.conf > /dev/null 2>&1; then
        print_success "Configuração do Samba válida"
        
        REALM_IN_CONFIG=$(grep "realm = " /etc/samba/smb.conf | awk '{print $3}')
        if [ "${REALM_IN_CONFIG}" == "${DOMAIN_REALM}" ]; then
            print_success "Realm correto: ${REALM_IN_CONFIG}"
        else
            print_error "Realm incorreto: ${REALM_IN_CONFIG} (esperado: ${DOMAIN_REALM})"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "Configuração do Samba inválida"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    print_error "Ficheiro /etc/samba/smb.conf NÃO existe"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Teste 5: Winbind (se estiver a correr)
print_info "Teste 5: Verificando Winbind..."
if systemctl is-active --quiet winbind 2>/dev/null; then
    print_success "Serviço winbind está ativo"
    
    if wbinfo --ping-dc > /dev/null 2>&1; then
        print_success "Winbind consegue contactar o DC"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "Winbind NÃO consegue contactar o DC"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    print_info "Testando listagem de utilizadores..."
    USERS=$(wbinfo -u 2>/dev/null | wc -l)
    if [ "$USERS" -gt 0 ]; then
        print_success "Winbind lista ${USERS} utilizadores"
        print_info "Primeiros 5 utilizadores:"
        wbinfo -u | head -n 5
    else
        print_error "Winbind não consegue listar utilizadores"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    print_info "Testando listagem de grupos..."
    GROUPS=$(wbinfo -g 2>/dev/null | wc -l)
    if [ "$GROUPS" -gt 0 ]; then
        print_success "Winbind lista ${GROUPS} grupos"
        print_info "Primeiros 5 grupos:"
        wbinfo -g | head -n 5
    else
        print_error "Winbind não consegue listar grupos"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    print_warning "Serviço winbind não está ativo"
    print_info "Execute: sudo systemctl start winbind"
    TESTS_WARNING=$((TESTS_WARNING + 1))
fi

# Teste 6: SSSD (se estiver configurado)
print_info "Teste 6: Verificando SSSD..."
if [ -f /etc/sssd/sssd.conf ]; then
    print_success "Ficheiro /etc/sssd/sssd.conf existe"
    
    if [ "$(stat -c %a /etc/sssd/sssd.conf)" == "600" ]; then
        print_success "Permissões do sssd.conf corretas (600)"
    else
        print_warning "Permissões do sssd.conf incorretas: $(stat -c %a /etc/sssd/sssd.conf)"
        print_info "Recomendado: chmod 600 /etc/sssd/sssd.conf"
        TESTS_WARNING=$((TESTS_WARNING + 1))
    fi
    
    if systemctl is-active --quiet sssd 2>/dev/null; then
        print_success "Serviço SSSD está ativo"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_warning "Serviço SSSD não está ativo"
        print_info "Execute: sudo systemctl start sssd"
        TESTS_WARNING=$((TESTS_WARNING + 1))
    fi
else
    print_warning "SSSD não está configurado"
    print_info "SSSD é opcional mas recomendado"
    TESTS_WARNING=$((TESTS_WARNING + 1))
fi

# Teste 7: NSS/PAM (getent)
print_info "Teste 7: Verificando resolução de utilizadores (NSS)..."
if getent passwd administrator@${DOMAIN_DNS_NAME} > /dev/null 2>&1; then
    print_success "NSS consegue resolver administrator@${DOMAIN_DNS_NAME}"
    print_info "Informação do utilizador:"
    getent passwd administrator@${DOMAIN_DNS_NAME}
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    print_error "NSS NÃO consegue resolver administrator@${DOMAIN_DNS_NAME}"
    print_info "Verifique /etc/nsswitch.conf e se o Winbind/SSSD está a correr"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Teste 8: Sincronização de relógio
print_info "Teste 8: Verificando sincronização de relógio..."
print_info "Data/Hora local: $(date)"
print_warning "Verifique manualmente se o relógio está sincronizado com o servidor AD"
print_info "Diferença máxima permitida: 5 minutos"
TESTS_WARNING=$((TESTS_WARNING + 1))

###############################################################################
# Resumo
###############################################################################

print_header "Resumo da Verificação"

echo -e "${GREEN}Testes Passou: ${TESTS_PASSED}${NC}"
echo -e "${YELLOW}Avisos: ${TESTS_WARNING}${NC}"
echo -e "${RED}Testes Falharam: ${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    if [ $TESTS_WARNING -eq 0 ]; then
        print_success "TODAS AS VERIFICAÇÕES PASSARAM!"
        echo ""
        print_info "A máquina está corretamente aderida ao domínio ${DOMAIN_REALM}"
        print_info "Os utilizadores do domínio podem fazer login"
        exit 0
    else
        print_warning "VERIFICAÇÕES PASSARAM COM AVISOS"
        echo ""
        print_info "A máquina está aderida ao domínio mas há algumas questões menores"
        print_info "Reveja os avisos acima"
        exit 0
    fi
else
    print_error "ALGUMAS VERIFICAÇÕES FALHARAM"
    echo ""
    print_info "A máquina pode não estar corretamente aderida ao domínio"
    print_info "Reveja os erros acima e corrija antes de prosseguir"
    echo ""
    print_info "Passos de troubleshooting:"
    print_info "  1. Verifique os logs: journalctl -xeu winbind"
    print_info "  2. Verifique os logs do Samba: tail -f /var/log/samba/*.log"
    print_info "  3. Verifique o DNS: host -t SRV _ldap._tcp.${DOMAIN_DNS_NAME}"
    print_info "  4. Tente re-aderir: net ads leave -U administrator && net ads join -U administrator"
    exit 1
fi
