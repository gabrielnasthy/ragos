#!/bin/bash

###############################################################################
# Script: prepare-golden-image-for-domain.sh
# Descrição: Prepara a Golden Image (chroot) para adesão ao domínio Samba AD
# Autor: RAGOS Agent
# Versão: 1.0
# Data: 2025-11-17
#
# AVISO: Este script deve ser executado DENTRO do chroot da Golden Image.
#        Exemplo: sudo arch-chroot /mnt/ragostorage/nfs_root
#                 ./prepare-golden-image-for-domain.sh
###############################################################################

set -e  # Parar em caso de erro

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
AD_SERVER_IP="10.0.3.1"
NTP_SERVER="pool.ntp.org"  # Ou use $AD_SERVER_IP se não houver Internet

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

check_chroot() {
    if [ "$(stat -c %d:%i /)" == "$(stat -c %d:%i /proc/1/root/.)" ]; then
        print_error "Este script deve ser executado DENTRO do chroot!"
        print_info "Execute: sudo arch-chroot /mnt/ragostorage/nfs_root"
        exit 1
    fi
}

###############################################################################
# Passo 1: Verificar que estamos no chroot
###############################################################################

print_header "Verificando Ambiente"
check_chroot
print_success "Executando dentro do chroot"

###############################################################################
# Passo 2: Configurar DNS
###############################################################################

print_header "Configurando DNS"

print_info "Criando /etc/resolv.conf..."
cat > /etc/resolv.conf << EOF
search ${DOMAIN_DNS_NAME}
nameserver ${AD_SERVER_IP}
EOF

print_success "/etc/resolv.conf criado"
cat /etc/resolv.conf

print_info "Testando resolução DNS..."
if host -t A ${DOMAIN_DNS_NAME} > /dev/null 2>&1; then
    print_success "DNS está a funcionar: $(host -t A ${DOMAIN_DNS_NAME})"
else
    print_error "Falha na resolução DNS de ${DOMAIN_DNS_NAME}"
    print_warning "Verifique se o servidor AD está a correr e acessível"
    exit 1
fi

if host -t SRV _ldap._tcp.${DOMAIN_DNS_NAME} > /dev/null 2>&1; then
    print_success "Registros SRV encontrados"
else
    print_warning "Registros SRV não encontrados - pode causar problemas"
fi

###############################################################################
# Passo 3: Sincronizar Relógio
###############################################################################

print_header "Sincronizando Relógio"

print_info "Verificando se o pacote 'ntp' está instalado..."
if ! pacman -Qi ntp > /dev/null 2>&1; then
    print_warning "Pacote 'ntp' não encontrado. Instalando..."
    pacman -S --noconfirm ntp
    print_success "Pacote 'ntp' instalado"
else
    print_success "Pacote 'ntp' já está instalado"
fi

print_info "Sincronizando com ${NTP_SERVER}..."
if sntp -s ${NTP_SERVER} > /dev/null 2>&1; then
    print_success "Relógio sincronizado"
    print_info "Data/Hora atual: $(date)"
else
    print_error "Falha na sincronização do relógio com ${NTP_SERVER}"
    print_warning "Tentando com o servidor AD (${AD_SERVER_IP})..."
    if sntp -s ${AD_SERVER_IP} > /dev/null 2>&1; then
        print_success "Relógio sincronizado com o servidor AD"
        print_info "Data/Hora atual: $(date)"
    else
        print_error "Falha na sincronização do relógio"
        print_warning "A adesão ao domínio pode falhar se o relógio estiver dessincronizado"
    fi
fi

###############################################################################
# Passo 4: Criar Configuração do Samba
###############################################################################

print_header "Configurando Samba"

print_info "Criando diretório /etc/samba..."
mkdir -p /etc/samba

print_info "Criando /etc/samba/smb.conf..."
cat > /etc/samba/smb.conf << 'EOF'
[global]
    # Identificação do Domínio
    workgroup = WORKGROUP_PLACEHOLDER
    realm = REALM_PLACEHOLDER
    security = ADS

    # Servidor de Autenticação
    password server = AD_SERVER_PLACEHOLDER

    # Kerberos
    kerberos method = secrets and keytab
    dedicated keytab file = /etc/krb5.keytab

    # DNS e Resolução de Nomes
    name resolve order = host wins bcast

    # ID Mapping (configuração básica)
    idmap config * : backend = tdb
    idmap config * : range = 3000000-3999999
    
    idmap config WORKGROUP_PLACEHOLDER : backend = rid
    idmap config WORKGROUP_PLACEHOLDER : range = 10000-999999

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

# Substituir placeholders
sed -i "s/WORKGROUP_PLACEHOLDER/${DOMAIN_WORKGROUP}/g" /etc/samba/smb.conf
sed -i "s/REALM_PLACEHOLDER/${DOMAIN_REALM}/g" /etc/samba/smb.conf
sed -i "s/AD_SERVER_PLACEHOLDER/${AD_SERVER_FQDN}/g" /etc/samba/smb.conf

print_success "/etc/samba/smb.conf criado"

print_info "Verificando configuração com testparm..."
if testparm -s /etc/samba/smb.conf > /dev/null 2>&1; then
    print_success "Configuração do Samba válida"
else
    print_error "Configuração do Samba contém erros"
    testparm -s /etc/samba/smb.conf
    exit 1
fi

###############################################################################
# Passo 5: Criar Configuração do Kerberos
###############################################################################

print_header "Configurando Kerberos"

print_info "Criando /etc/krb5.conf..."
cat > /etc/krb5.conf << 'EOF'
[libdefaults]
    default_realm = REALM_PLACEHOLDER
    dns_lookup_realm = true
    dns_lookup_kdc = true
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    REALM_PLACEHOLDER = {
        kdc = AD_SERVER_PLACEHOLDER
        admin_server = AD_SERVER_PLACEHOLDER
        default_domain = DOMAIN_DNS_PLACEHOLDER
    }

[domain_realm]
    .DOMAIN_DNS_PLACEHOLDER = REALM_PLACEHOLDER
    DOMAIN_DNS_PLACEHOLDER = REALM_PLACEHOLDER

[logging]
    default = FILE:/var/log/krb5libs.log
    kdc = FILE:/var/log/krb5kdc.log
    admin_server = FILE:/var/log/kadmind.log
EOF

# Substituir placeholders
sed -i "s/REALM_PLACEHOLDER/${DOMAIN_REALM}/g" /etc/krb5.conf
sed -i "s/AD_SERVER_PLACEHOLDER/${AD_SERVER_FQDN}/g" /etc/krb5.conf
sed -i "s/DOMAIN_DNS_PLACEHOLDER/${DOMAIN_DNS_NAME}/g" /etc/krb5.conf

print_success "/etc/krb5.conf criado"

print_info "Testando autenticação Kerberos..."
print_warning "Será solicitada a password do administrator@${DOMAIN_REALM}"
print_info "Executando: kinit administrator@${DOMAIN_REALM}"

if kinit administrator@${DOMAIN_REALM}; then
    print_success "Autenticação Kerberos bem-sucedida"
    
    print_info "Verificando ticket Kerberos..."
    klist
    
    print_info "Destruindo ticket de teste..."
    kdestroy
    print_success "Ticket destruído"
else
    print_error "Falha na autenticação Kerberos"
    print_warning "Verifique:"
    print_warning "  1. A password do administrator está correta"
    print_warning "  2. O relógio está sincronizado"
    print_warning "  3. O DNS está a resolver ${DOMAIN_REALM}"
    exit 1
fi

###############################################################################
# Passo 6: Informações Finais
###############################################################################

print_header "Preparação Concluída"

print_success "A Golden Image está pronta para aderir ao domínio!"
echo ""
print_info "Próximo passo: Execute o comando de adesão ao domínio:"
echo -e "${GREEN}    net ads join -U administrator${NC}"
echo ""
print_info "Após a adesão, verifique com:"
echo -e "${GREEN}    wbinfo --ping-dc${NC}"
echo -e "${GREEN}    wbinfo -u${NC}"
echo -e "${GREEN}    getent passwd administrator@${DOMAIN_DNS_NAME}${NC}"
echo ""
print_warning "IMPORTANTE: Se receber 'Preauthentication failed':"
print_warning "  1. Verifique se o relógio está sincronizado: date"
print_warning "  2. Re-sincronize se necessário: sntp -s ${NTP_SERVER}"
print_warning "  3. Tente novamente o 'net ads join'"
echo ""

exit 0
