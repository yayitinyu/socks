#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

TEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=$(cd -- "${TEST_DIR}/.." && pwd)
SCRIPT_PATH="${PROJECT_DIR}/socks5.sh"
TEMP_CONFIG=""
TEMP_CONFIG_PRIVATE=""
TEMP_CONFIG_DUAL=""
TEMP_CONFIG_LEGACY=""
TEMP_HELPER=""
TEMP_HELPER_DUAL=""
TEMP_HELPER_ANY=""
TEMP_UFW_HELPER=""
TEMP_UFW_HELPER_ANY=""
TEMP_FIREWALLD_HELPER=""
TEMP_IPTABLES_HELPER=""
TEMP_SERVICE=""
TEMP_STATE=""
TEMP_STATE_LEGACY=""
DANTE_VERSION_SANDBOX=""
FIREWALL_SANDBOX=""

cleanup() {
    [[ -z "$TEMP_CONFIG" || ! -f "$TEMP_CONFIG" ]] || rm -f -- "$TEMP_CONFIG"
    [[ -z "$TEMP_CONFIG_PRIVATE" || ! -f "$TEMP_CONFIG_PRIVATE" ]] || rm -f -- "$TEMP_CONFIG_PRIVATE"
    [[ -z "$TEMP_CONFIG_DUAL" || ! -f "$TEMP_CONFIG_DUAL" ]] || rm -f -- "$TEMP_CONFIG_DUAL"
    [[ -z "$TEMP_CONFIG_LEGACY" || ! -f "$TEMP_CONFIG_LEGACY" ]] || rm -f -- "$TEMP_CONFIG_LEGACY"
    [[ -z "$TEMP_HELPER" || ! -f "$TEMP_HELPER" ]] || rm -f -- "$TEMP_HELPER"
    [[ -z "$TEMP_HELPER_DUAL" || ! -f "$TEMP_HELPER_DUAL" ]] || rm -f -- "$TEMP_HELPER_DUAL"
    [[ -z "$TEMP_HELPER_ANY" || ! -f "$TEMP_HELPER_ANY" ]] || rm -f -- "$TEMP_HELPER_ANY"
    [[ -z "$TEMP_UFW_HELPER" || ! -f "$TEMP_UFW_HELPER" ]] || rm -f -- "$TEMP_UFW_HELPER"
    [[ -z "$TEMP_UFW_HELPER_ANY" || ! -f "$TEMP_UFW_HELPER_ANY" ]] || rm -f -- "$TEMP_UFW_HELPER_ANY"
    [[ -z "$TEMP_FIREWALLD_HELPER" || ! -f "$TEMP_FIREWALLD_HELPER" ]] || rm -f -- "$TEMP_FIREWALLD_HELPER"
    [[ -z "$TEMP_IPTABLES_HELPER" || ! -f "$TEMP_IPTABLES_HELPER" ]] || rm -f -- "$TEMP_IPTABLES_HELPER"
    [[ -z "$TEMP_SERVICE" || ! -f "$TEMP_SERVICE" ]] || rm -f -- "$TEMP_SERVICE"
    [[ -z "$TEMP_STATE" || ! -f "$TEMP_STATE" ]] || rm -f -- "$TEMP_STATE"
    [[ -z "$TEMP_STATE_LEGACY" || ! -f "$TEMP_STATE_LEGACY" ]] || rm -f -- "$TEMP_STATE_LEGACY"
    if [[ -n "$DANTE_VERSION_SANDBOX" && -d "$DANTE_VERSION_SANDBOX" ]]; then
        rm -f -- "$DANTE_VERSION_SANDBOX/danted"
        rmdir -- "$DANTE_VERSION_SANDBOX"
    fi
    if [[ -n "$FIREWALL_SANDBOX" && -d "$FIREWALL_SANDBOX" ]]; then
        rm -f -- \
            "$FIREWALL_SANDBOX/bin/ufw" \
            "$FIREWALL_SANDBOX/bin/nft" \
            "$FIREWALL_SANDBOX/bin/firewall-cmd" \
            "$FIREWALL_SANDBOX/bin/iptables" \
            "$FIREWALL_SANDBOX/bin/semanage" \
            "$FIREWALL_SANDBOX/ufw.state" \
            "$FIREWALL_SANDBOX/nft.state" \
            "$FIREWALL_SANDBOX/firewalld-permanent.state" \
            "$FIREWALL_SANDBOX/firewalld-runtime.state" \
            "$FIREWALL_SANDBOX/iptables.state" \
            "$FIREWALL_SANDBOX/selinux.state"
        rmdir -- "$FIREWALL_SANDBOX/bin" "$FIREWALL_SANDBOX"
    fi
}
trap cleanup EXIT

export SOCKS5_NODE_LIB_ONLY=1
# shellcheck disable=SC1090
source "$SCRIPT_PATH"

TESTS_RUN=0

pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf 'ok %d - %s\n' "$TESTS_RUN" "$1"
}

fail() {
    printf 'not ok %d - %s\n' "$((TESTS_RUN + 1))" "$1" >&2
    exit 1
}

assert_true() {
    local description=$1
    shift
    if "$@"; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_false() {
    local description=$1
    shift
    if "$@"; then
        fail "$description"
    else
        pass "$description"
    fi
}

assert_contains() {
    local description=$1
    local file=$2
    local expected=$3

    if grep -Fq -- "$expected" "$file"; then
        pass "$description"
    else
        printf 'Missing text: %s\n' "$expected" >&2
        fail "$description"
    fi
}

assert_not_contains() {
    local description=$1
    local file=$2
    local unexpected=$3

    if grep -Fq -- "$unexpected" "$file"; then
        printf 'Unexpected text: %s\n' "$unexpected" >&2
        fail "$description"
    else
        pass "$description"
    fi
}

assert_file_exists() {
    local description=$1
    local file=$2

    if [[ -f "$file" ]]; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_line_order() {
    local description=$1
    local file=$2
    local first_pattern=$3
    local second_pattern=$4
    local first_line second_line

    first_line=$(awk -v pattern="$first_pattern" '$0 ~ pattern { print NR; exit }' "$file")
    second_line=$(awk -v pattern="$second_pattern" '$0 ~ pattern { print NR; exit }' "$file")
    if [[ -n "$first_line" && -n "$second_line" ]] && ((first_line < second_line)); then
        pass "$description"
    else
        printf 'Expected %s before %s in %s\n' "$first_pattern" "$second_pattern" "$file" >&2
        fail "$description"
    fi
}

assert_file_absent() {
    local description=$1
    local file=$2

    if [[ -e "$file" ]]; then
        fail "$description"
    else
        pass "$description"
    fi
}

assert_true "accepts the lowest custom unprivileged port" is_valid_port 1025
assert_true "accepts port 65535" is_valid_port 65535
assert_false "rejects a privileged port" is_valid_port 1024
assert_false "rejects a port above 65535" is_valid_port 65536
assert_false "rejects a non-numeric port" is_valid_port 20x00
assert_false "rejects an overflowing numeric port" is_valid_port 18446744073709552640

assert_true "accepts generated-style usernames" is_valid_username s5u_deadbeef
assert_true "accepts a conventional username" is_valid_username proxy-user
assert_false "rejects an uppercase Linux username" is_valid_username ProxyUser
assert_false "rejects shell metacharacters in usernames" is_valid_username 'proxy;root'

assert_true "accepts a safe 12-character password" is_valid_password Abcdef1234._
assert_false "rejects a short password" is_valid_password short123
assert_false "rejects colon in passwords" is_valid_password 'Abcdef123456:'
assert_false "rejects shell metacharacters in passwords" is_valid_password 'Abcdef123456$'

assert_true "accepts an IPv4 host CIDR" is_valid_ipv4_cidr 203.0.113.8/32
assert_true "accepts the all-IPv4 CIDR" is_valid_ipv4_cidr 0.0.0.0/0
assert_false "rejects an IPv4 octet above 255" is_valid_ipv4_cidr 256.0.0.1/32
assert_false "rejects ambiguous leading zeroes" is_valid_ipv4_cidr 010.0.0.1/32
assert_false "rejects an oversized prefix" is_valid_ipv4_cidr 192.0.2.1/33

assert_true "accepts an IPv6 loopback address" is_valid_ipv6 ::1
assert_true "accepts an IPv6 unspecified address" is_valid_ipv6 ::
assert_true "accepts a global unicast IPv6 address" is_valid_ipv6 2001:db8::1
assert_true "accepts a full 8-block IPv6 address" is_valid_ipv6 2001:0db8:85a3:0000:0000:8a2e:0370:7334
assert_false "rejects triple colon in IPv6" is_valid_ipv6 2001:db8:::1
assert_false "rejects multiple double colons in IPv6" is_valid_ipv6 2001:db8::1::2
assert_false "rejects non-hex characters in IPv6" is_valid_ipv6 2001:xyz::1
assert_false "rejects block larger than 4 hex digits" is_valid_ipv6 2001:12345::1

assert_true "accepts an IPv6 CIDR" is_valid_ipv6_cidr 2001:db8::/32
assert_true "accepts an IPv6 host CIDR" is_valid_ipv6_cidr 2001:db8::1/128
assert_true "accepts the all-IPv6 CIDR" is_valid_ipv6_cidr ::/0
assert_false "rejects an oversized IPv6 prefix" is_valid_ipv6_cidr 2001:db8::/129

assert_true "accepts 0/0 CIDR wildcard" is_valid_cidr 0/0
assert_true "accepts IPv4 CIDR in is_valid_cidr" is_valid_cidr 192.0.2.0/24
assert_true "accepts IPv6 CIDR in is_valid_cidr" is_valid_cidr 2001:db8::/48

assert_true "accepts valid IPv4 host" is_valid_host 203.0.113.8
assert_true "accepts valid IPv6 host" is_valid_host 2001:db8::1
assert_true "accepts valid bracketed IPv6 host" is_valid_host "[2001:db8::1]"
assert_true "accepts valid domain host" is_valid_host nat.example.com
assert_true "accepts valid hyphenated domain" is_valid_host my-node-1.vps.net
assert_false "rejects url scheme in host" is_valid_host https://nat.example.com
assert_false "rejects spaces in host" is_valid_host "nat .com"
assert_false "rejects double dots in host" is_valid_host "nat..example.com"

if [[ "$(normalize_cidr 203.0.113.9)" == "203.0.113.9/32" ]]; then
    pass "normalizes a single IPv4 address to /32"
else
    fail "normalizes a single IPv4 address to /32"
fi

if [[ "$(normalize_cidr 2001:db8::1)" == "2001:db8::1/128" ]]; then
    pass "normalizes a single IPv6 address to /128"
else
    fail "normalizes a single IPv6 address to /128"
fi

if [[ "$(normalize_cidr 0/0)" == "0/0" ]]; then
    pass "normalizes 0/0 CIDR wildcard"
else
    fail "normalizes 0/0 CIDR wildcard"
fi

for _ in {1..32}; do
    generated_port=$(choose_random_port) || fail "generates a random high port"
    if ((generated_port < 20000 || generated_port > 60000)); then
        fail "keeps random ports in the documented range"
    fi
done
pass "keeps random ports in the documented range"

export SOCKS_PORT=45678
export EXTERNAL_INTERFACE=eth0
export DAEMON_USER=s5d_deadbeef
export AUTH_GROUP=s5g_deadbeef
export ALLOW_CIDR=203.0.113.8/32
export ALLOW_PRIVATE=0
TEMP_CONFIG=$(mktemp)
render_dante_config >"$TEMP_CONFIG"

assert_contains "binds the selected high port" "$TEMP_CONFIG" "internal: 0.0.0.0 port = 45678"
assert_contains "uses the detected egress interface" "$TEMP_CONFIG" "external: eth0"
assert_contains "drops privileges with the Dante 1.4.x directive" "$TEMP_CONFIG" "user.unprivileged: s5d_deadbeef"
assert_not_contains "does not emit the obsolete privilege directive" "$TEMP_CONFIG" "user.notprivileged:"
assert_contains "requires username authentication" "$TEMP_CONFIG" "socksmethod: username"
assert_contains "limits authenticated access to the managed group" "$TEMP_CONFIG" "group: s5g_deadbeef"
assert_contains "limits client source addresses" "$TEMP_CONFIG" "from: 203.0.113.8/32 to: 0/0"
assert_contains "matches destinations of both address families" "$TEMP_CONFIG" "from: 203.0.113.8/32 to: 0/0"
assert_contains "blocks cloud metadata and link-local targets" "$TEMP_CONFIG" "to: 169.254.0.0/16"
assert_contains "blocks IPv6 loopback targets" "$TEMP_CONFIG" "to: ::1/128"
assert_contains "blocks IPv6 private ULA targets" "$TEMP_CONFIG" "to: fc00::/7"
assert_contains "blocks IPv6 link-local targets" "$TEMP_CONFIG" "to: fe80::/10"
assert_contains "allows TCP CONNECT" "$TEMP_CONFIG" "command: connect"
assert_not_contains "does not enable UDP Associate" "$TEMP_CONFIG" "udpassociate"

export ALLOW_PRIVATE=1
TEMP_CONFIG_PRIVATE=$(mktemp)
render_dante_config >"$TEMP_CONFIG_PRIVATE"
assert_not_contains "allow-private removes private destination blocks" "$TEMP_CONFIG_PRIVATE" "socks block {"
export ALLOW_PRIVATE=0

# 出口协议栈：默认仅 IPv4，--dual-stack 才放开 IPv6
assert_contains "default egress restricts Dante to IPv4" "$TEMP_CONFIG" "external.protocol: ipv4"
assert_line_order "protocol keyword precedes the external interface" \
    "$TEMP_CONFIG" '^external[.]protocol:' '^external:'

export DUAL_STACK=1
TEMP_CONFIG_DUAL=$(mktemp)
render_dante_config >"$TEMP_CONFIG_DUAL"
assert_not_contains "--dual-stack keeps both address families" "$TEMP_CONFIG_DUAL" "external.protocol:"
assert_contains "--dual-stack still egresses via the detected interface" "$TEMP_CONFIG_DUAL" "external: eth0"

export DUAL_STACK=0
export DANTE_PROTOCOL_SUPPORTED=0
export EXTERNAL_ADDRESS=203.0.113.10
TEMP_CONFIG_LEGACY=$(mktemp)
render_dante_config >"$TEMP_CONFIG_LEGACY"
assert_not_contains "old Dante omits the unsupported protocol keyword" "$TEMP_CONFIG_LEGACY" "external.protocol:"
assert_contains "old Dante pins egress to the interface IPv4 address" "$TEMP_CONFIG_LEGACY" "external: 203.0.113.10"
export DANTE_PROTOCOL_SUPPORTED=1
export EXTERNAL_ADDRESS=""

DANTE_VERSION_SANDBOX=$(mktemp -d)
fake_dante_version() {
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$1" >"$DANTE_VERSION_SANDBOX/danted"
    chmod 700 "$DANTE_VERSION_SANDBOX/danted"
}
export DANTE_BIN="$DANTE_VERSION_SANDBOX/danted"
fake_dante_version "Dante v1.4.1"
assert_true "detects protocol keyword support on Dante 1.4.1" dante_supports_protocol_keyword
fake_dante_version "Dante v1.4.3"
assert_true "detects protocol keyword support on Dante 1.4.3" dante_supports_protocol_keyword
fake_dante_version "Dante v1.5.0"
assert_true "detects protocol keyword support on a newer major.minor" dante_supports_protocol_keyword
fake_dante_version "Dante v1.4.0"
assert_false "rejects protocol keyword support on Dante 1.4.0" dante_supports_protocol_keyword
fake_dante_version "Dante v1.3.2"
assert_false "rejects protocol keyword support on Dante 1.3.2" dante_supports_protocol_keyword
fake_dante_version "unparsable version banner"
assert_true "assumes protocol keyword support when the version is unreadable" dante_supports_protocol_keyword

export DANTE_BIN=/usr/sbin/danted
TEMP_SERVICE=$(mktemp)
render_service_unit >"$TEMP_SERVICE"
assert_contains "service uses a unique Dante PID file" "$TEMP_SERVICE" "-p /run/socks5-node/danted.pid"
assert_contains "service creates a private runtime directory" "$TEMP_SERVICE" "RuntimeDirectory=socks5-node"
assert_not_contains "service does not force a restrictive Dante umask" "$TEMP_SERVICE" "UMask="
assert_contains "service reads the SELinux-compatible config path" "$TEMP_SERVICE" "/etc/socks/socks5-node.conf"

export FIREWALL_BACKEND=nftables
export FIREWALL_ZONE=""
TEMP_HELPER=$(mktemp)
render_firewall_helper >"$TEMP_HELPER"
assert_true "generated firewall helper has valid Bash syntax" bash -n "$TEMP_HELPER"
assert_contains "firewall helper carries the selected port" "$TEMP_HELPER" "PORT=45678"
assert_contains "firewall helper carries the source CIDR" "$TEMP_HELPER" "ALLOW_CIDR=203.0.113.8/32"
assert_contains "firewall helper carries the egress stack mode" "$TEMP_HELPER" "DUAL_STACK=0"
assert_contains "nftables rule has an ownership comment" "$TEMP_HELPER" "comment \"\$COMMENT\""
assert_contains "iptables rule has an ownership comment" "$TEMP_HELPER" "--comment \"\$COMMENT\""

export DUAL_STACK=1
TEMP_HELPER_DUAL=$(mktemp)
render_firewall_helper >"$TEMP_HELPER_DUAL"
assert_true "dual-stack firewall helper has valid Bash syntax" bash -n "$TEMP_HELPER_DUAL"
assert_contains "dual-stack firewall helper records the stack mode" "$TEMP_HELPER_DUAL" "DUAL_STACK=1"
assert_contains "IPv4-only mode narrows wildcard nftables rules" "$TEMP_HELPER" "meta nfproto ipv4 tcp dport"
assert_contains "IPv4-only mode narrows wildcard ufw rules" "$TEMP_HELPER" "ufw allow proto tcp from 0.0.0.0/0 to any port"
export DUAL_STACK=0

FIREWALL_SANDBOX=$(mktemp -d)
mkdir -p "$FIREWALL_SANDBOX/bin"

cat >"$FIREWALL_SANDBOX/bin/ufw" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${1:-}" in
    status)
        if [[ "${FAKE_UFW_INACTIVE:-0}" == "1" ]]; then
            printf 'Status: inactive\n'
        else
            printf 'Status: active\n'
        fi
        if [[ -f "$FAKE_UFW_STATE" && "${FAKE_UFW_INACTIVE:-0}" != "1" ]]; then
            if [[ "${2:-}" == "numbered" ]]; then
                printf '[ 1] 45678/tcp ALLOW IN 203.0.113.8/32 # socks5-node-45678\n'
            else
                printf '45678/tcp ALLOW IN 203.0.113.8/32 # socks5-node-45678\n'
            fi
        fi
        ;;
    show)
        [[ "${2:-}" == "added" ]]
        if [[ -f "$FAKE_UFW_STATE" ]]; then
            printf "ufw allow from 203.0.113.8/32 to any port 45678 proto tcp comment 'socks5-node-45678'\n"
        fi
        ;;
    allow)
        : >"$FAKE_UFW_STATE"
        ;;
    --force)
        [[ "${2:-}" == "delete" && ("${3:-}" == "1" || "${3:-}" == "allow") ]]
        rm -f -- "$FAKE_UFW_STATE"
        ;;
    *)
        exit 2
        ;;
esac
EOF
chmod 700 "$FIREWALL_SANDBOX/bin/ufw"

export FIREWALL_BACKEND=ufw
TEMP_UFW_HELPER=$(mktemp)
render_firewall_helper >"$TEMP_UFW_HELPER"
chmod 700 "$TEMP_UFW_HELPER"
FAKE_UFW_STATE="$FIREWALL_SANDBOX/ufw.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_UFW_HELPER" add
assert_file_exists "UFW add creates the owned rule" "$FIREWALL_SANDBOX/ufw.state"
FAKE_UFW_STATE="$FIREWALL_SANDBOX/ufw.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_UFW_HELPER" remove
assert_file_absent "UFW remove deletes the owned rule by comment" "$FIREWALL_SANDBOX/ufw.state"
: >"$FIREWALL_SANDBOX/ufw.state"
FAKE_UFW_INACTIVE=1 FAKE_UFW_STATE="$FIREWALL_SANDBOX/ufw.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_UFW_HELPER" remove
assert_file_absent "UFW remove also clears a persistent rule while inactive" "$FIREWALL_SANDBOX/ufw.state"

cat >"$FIREWALL_SANDBOX/bin/firewall-cmd" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" == "--state" ]]; then
    exit 0
fi

state_file=$FAKE_FIREWALLD_RUNTIME_STATE
action=""
for argument in "$@"; do
    case "$argument" in
        --permanent) state_file=$FAKE_FIREWALLD_PERMANENT_STATE ;;
        --query-rich-rule=*) action=query ;;
        --add-rich-rule=*) action=add ;;
        --remove-rich-rule=*) action=remove ;;
    esac
done

case "$action" in
    query) [[ -f "$state_file" ]] ;;
    add) : >"$state_file" ;;
    remove) rm -f -- "$state_file" ;;
    *) exit 2 ;;
esac
EOF
chmod 700 "$FIREWALL_SANDBOX/bin/firewall-cmd"

export FIREWALL_BACKEND=firewalld
export FIREWALL_ZONE=public
TEMP_FIREWALLD_HELPER=$(mktemp)
render_firewall_helper >"$TEMP_FIREWALLD_HELPER"
chmod 700 "$TEMP_FIREWALLD_HELPER"
FAKE_FIREWALLD_PERMANENT_STATE="$FIREWALL_SANDBOX/firewalld-permanent.state" \
    FAKE_FIREWALLD_RUNTIME_STATE="$FIREWALL_SANDBOX/firewalld-runtime.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_FIREWALLD_HELPER" add
assert_file_exists "firewalld add creates a persistent rich rule" "$FIREWALL_SANDBOX/firewalld-permanent.state"
assert_file_exists "firewalld add creates a runtime rich rule" "$FIREWALL_SANDBOX/firewalld-runtime.state"
FAKE_FIREWALLD_PERMANENT_STATE="$FIREWALL_SANDBOX/firewalld-permanent.state" \
    FAKE_FIREWALLD_RUNTIME_STATE="$FIREWALL_SANDBOX/firewalld-runtime.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_FIREWALLD_HELPER" remove
assert_file_absent "firewalld remove clears the persistent rich rule" "$FIREWALL_SANDBOX/firewalld-permanent.state"
assert_file_absent "firewalld remove clears the runtime rich rule" "$FIREWALL_SANDBOX/firewalld-runtime.state"

cat >"$FIREWALL_SANDBOX/bin/iptables" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

case "${3:-}" in
    -S) exit 0 ;;
    -C) [[ -f "$FAKE_IPTABLES_STATE" ]] ;;
    -I) : >"$FAKE_IPTABLES_STATE" ;;
    -D) rm -f -- "$FAKE_IPTABLES_STATE" ;;
    *) exit 2 ;;
esac
EOF
chmod 700 "$FIREWALL_SANDBOX/bin/iptables"

export FIREWALL_BACKEND=iptables
export FIREWALL_ZONE=""
TEMP_IPTABLES_HELPER=$(mktemp)
render_firewall_helper >"$TEMP_IPTABLES_HELPER"
chmod 700 "$TEMP_IPTABLES_HELPER"
FAKE_IPTABLES_STATE="$FIREWALL_SANDBOX/iptables.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_IPTABLES_HELPER" add
assert_file_exists "iptables add creates the owned rule" "$FIREWALL_SANDBOX/iptables.state"
FAKE_IPTABLES_STATE="$FIREWALL_SANDBOX/iptables.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_IPTABLES_HELPER" remove
assert_file_absent "iptables remove clears the owned rule" "$FIREWALL_SANDBOX/iptables.state"

cat >"$FIREWALL_SANDBOX/bin/nft" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$*" == "-a list ruleset" ]]; then
    cat <<RULESET
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
    }
}
RULESET
elif [[ "${1:-} ${2:-} ${3:-}" == "-a list chain" ]]; then
    printf 'table inet filter {\n    chain input {\n'
    if [[ -f "$FAKE_NFT_STATE" ]]; then
        printf '        ip saddr 203.0.113.8/32 tcp dport 45678 counter accept comment "socks5-node-45678" # handle 7\n'
    fi
    printf '    }\n}\n'
elif [[ "${1:-}" == "insert" ]]; then
    : >"$FAKE_NFT_STATE"
elif [[ "${1:-} ${2:-}" == "delete rule" ]]; then
    [[ "$*" == *" handle 7" ]]
    rm -f -- "$FAKE_NFT_STATE"
else
    exit 2
fi
EOF
chmod 700 "$FIREWALL_SANDBOX/bin/nft"

export FIREWALL_BACKEND=nftables
FAKE_NFT_STATE="$FIREWALL_SANDBOX/nft.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_HELPER" add
assert_file_exists "nftables add creates the owned rule" "$FIREWALL_SANDBOX/nft.state"
FAKE_NFT_STATE="$FIREWALL_SANDBOX/nft.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_HELPER" remove
assert_file_absent "nftables remove deletes the owned rule by handle" "$FIREWALL_SANDBOX/nft.state"

# 通配来源 + 仅 IPv4：真正执行生成的 helper，确认新分支在 set -e 下能跑通
export ALLOW_CIDR=0/0
TEMP_HELPER_ANY=$(mktemp)
render_firewall_helper >"$TEMP_HELPER_ANY"
chmod 700 "$TEMP_HELPER_ANY"
FAKE_NFT_STATE="$FIREWALL_SANDBOX/nft.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_HELPER_ANY" add
assert_file_exists "IPv4-only wildcard source applies an nftables rule" "$FIREWALL_SANDBOX/nft.state"
FAKE_NFT_STATE="$FIREWALL_SANDBOX/nft.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_HELPER_ANY" remove
assert_file_absent "IPv4-only wildcard nftables rule is removed" "$FIREWALL_SANDBOX/nft.state"

export FIREWALL_BACKEND=ufw
TEMP_UFW_HELPER_ANY=$(mktemp)
render_firewall_helper >"$TEMP_UFW_HELPER_ANY"
chmod 700 "$TEMP_UFW_HELPER_ANY"
rm -f -- "$FIREWALL_SANDBOX/ufw.state"
FAKE_UFW_STATE="$FIREWALL_SANDBOX/ufw.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_UFW_HELPER_ANY" add
assert_file_exists "IPv4-only wildcard source applies a UFW rule" "$FIREWALL_SANDBOX/ufw.state"
FAKE_UFW_STATE="$FIREWALL_SANDBOX/ufw.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" "$TEMP_UFW_HELPER_ANY" remove
assert_file_absent "IPv4-only wildcard UFW rule is removed" "$FIREWALL_SANDBOX/ufw.state"

export ALLOW_CIDR=203.0.113.8/32
export FIREWALL_BACKEND=nftables

cat >"$FIREWALL_SANDBOX/bin/semanage" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "$*" == "port -l" ]]; then
    printf 'SELinux Port Type              Proto    Port Number\n'
    printf 'ephemeral_port_t               tcp      32768-60999\n'
    printf 'socks_port_t                   tcp      1080\n'
elif [[ "$*" == "port -l -C" ]]; then
    printf 'SELinux Port Type              Proto    Port Number\n'
    if [[ -f "$FAKE_SELINUX_STATE" ]]; then
        printf 'socks_port_t                   tcp      45678\n'
    fi
elif [[ "${1:-} ${2:-}" == "port -a" || "${1:-} ${2:-}" == "port -m" ]]; then
    : >"$FAKE_SELINUX_STATE"
elif [[ "${1:-} ${2:-}" == "port -d" ]]; then
    rm -f -- "$FAKE_SELINUX_STATE"
else
    exit 2
fi
EOF
chmod 700 "$FIREWALL_SANDBOX/bin/semanage"

if [[ "$(FAKE_SELINUX_STATE="$FIREWALL_SANDBOX/selinux.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" selinux_port_type_for 45678 0)" == "ephemeral_port_t" ]]; then
    pass "SELinux parser resolves a port inside a policy range"
else
    fail "SELinux parser resolves a port inside a policy range"
fi

port_in_use() { return 1; }
export SELINUX_ENABLED=1
export SELINUX_PORT_MANAGED=0
export SOCKS_PORT=45678
export CLI_PORT=""
FAKE_SELINUX_STATE="$FIREWALL_SANDBOX/selinux.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" configure_selinux_port 1 0
assert_file_exists "SELinux setup creates a socks_port_t override" "$FIREWALL_SANDBOX/selinux.state"
if ((SELINUX_PORT_MANAGED == 1)); then
    pass "SELinux setup records ownership of its override"
else
    fail "SELinux setup records ownership of its override"
fi
FAKE_SELINUX_STATE="$FIREWALL_SANDBOX/selinux.state" \
    PATH="$FIREWALL_SANDBOX/bin:$PATH" remove_selinux_port_mapping
assert_file_absent "SELinux cleanup removes only the managed override" "$FIREWALL_SANDBOX/selinux.state"

TEMP_STATE=$(mktemp)
export STATE_FILE=$TEMP_STATE
export SOCKS_PORT=45678
export SOCKS_USERNAME=s5u_deadbeef
export SOCKS_PASSWORD=abcdef0123456789abcdef01
export ALLOW_CIDR=203.0.113.8/32
export ALLOW_PRIVATE=0
export EXTERNAL_INTERFACE=eth0
export DANTE_BIN=/usr/sbin/danted
export FIREWALL_BACKEND=ufw
export FIREWALL_ZONE=""
export AUTH_GROUP=s5g_deadbeef
export AUTH_GROUP_GID=991
export AUTH_USER_UID=992
export DAEMON_USER=s5d_deadbeef
export DAEMON_USER_UID=993
export DAEMON_GROUP=s5d_deadbeef
export DAEMON_GROUP_GID=994
export INSTALLED_AT=2026-08-10T00:00:00Z
export DANTE_WAS_PRESENT=0
export DANTE_CONFIG_DIR_CREATED=1
export SELINUX_ENABLED=1
export SELINUX_PORT_MANAGED=1
render_state >"$TEMP_STATE"
load_state
if [[ "$SOCKS_USERNAME" == "s5u_deadbeef" \
    && "$SOCKS_PASSWORD" == "abcdef0123456789abcdef01" \
    && "$SELINUX_PORT_MANAGED" == "1" ]]; then
    pass "state round-trip preserves credentials and ownership markers"
else
    fail "state round-trip preserves credentials and ownership markers"
fi

assert_contains "state records the egress stack mode" "$TEMP_STATE" "DUAL_STACK="

# 旧状态文件没有 DUAL_STACK，当时的出口行为是双栈，加载时应补成 1
TEMP_STATE_LEGACY=$(mktemp)
grep -v '^DUAL_STACK=' "$TEMP_STATE" >"$TEMP_STATE_LEGACY"
(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    export STATE_FILE=$TEMP_STATE_LEGACY
    load_state
    [[ "$DUAL_STACK" == "1" ]]
) || fail "legacy state without DUAL_STACK keeps dual-stack egress"
pass "legacy state without DUAL_STACK keeps dual-stack egress"

# ==================== Alpine OpenRC Tests ====================
ALPINESCRIPT_PATH="${PROJECT_DIR}/socks5_alpine.sh"
assert_true "socks5_alpine.sh has valid Bash syntax" bash -n "$ALPINESCRIPT_PATH"

TEMP_ALPINE_SERVICE=$(mktemp)
TEMP_ALPINE_FIREWALL_INIT=$(mktemp)
TEMP_ALPINE_CONFIG=$(mktemp)
TEMP_ALPINE_CONFIG_DUAL=$(mktemp)
TEMP_ALPINE_STATE=$(mktemp)

# Source socks5_alpine.sh in isolation
(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$ALPINESCRIPT_PATH"

    export SOCKS_PORT=45678
    export EXTERNAL_INTERFACE=eth0
    export DAEMON_USER=s5d_deadbeef
    export AUTH_GROUP=s5g_deadbeef
    export ALLOW_CIDR=203.0.113.8/32
    export ALLOW_PRIVATE=0
    export DANTE_BIN=/usr/sbin/sockd
    export LOG_FILE=/var/log/socks5-node.log

    render_dante_config >"$TEMP_ALPINE_CONFIG"
    DUAL_STACK=1 render_dante_config >"$TEMP_ALPINE_CONFIG_DUAL"
    render_service_init >"$TEMP_ALPINE_SERVICE"
    render_firewall_init >"$TEMP_ALPINE_FIREWALL_INIT"

    export STATE_FILE=$TEMP_ALPINE_STATE
    export SOCKS_USERNAME=s5u_deadbeef
    export SOCKS_PASSWORD=abcdef0123456789abcdef01
    export FIREWALL_BACKEND=iptables
    export FIREWALL_ZONE=""
    export AUTH_GROUP_GID=991
    export AUTH_USER_UID=992
    export DAEMON_USER_UID=993
    export DAEMON_GROUP=s5d_deadbeef
    export DAEMON_GROUP_GID=994
    export INSTALLED_AT=2026-08-10T00:00:00Z
    export DANTE_WAS_PRESENT=0
    export DANTE_CONFIG_DIR_CREATED=1
    export SELINUX_ENABLED=0
    export SELINUX_PORT_MANAGED=0
    render_state >"$TEMP_ALPINE_STATE"
    load_state
    [[ "$SOCKS_USERNAME" == "s5u_deadbeef" && "$SOCKS_PASSWORD" == "abcdef0123456789abcdef01" ]]
) || fail "socks5_alpine.sh basic runtime execution"
pass "socks5_alpine.sh basic runtime execution"

assert_contains "Alpine service init uses openrc-run shebang" "$TEMP_ALPINE_SERVICE" "#!/sbin/openrc-run"
assert_contains "Alpine service init executes sockd" "$TEMP_ALPINE_SERVICE" 'command="/usr/sbin/sockd"'
assert_contains "Alpine service init passes daemon arguments" "$TEMP_ALPINE_SERVICE" 'command_args="-D -p /run/socks5-node/sockd.pid -f /etc/socks/socks5-node.conf"'
assert_contains "Alpine service init specifies pidfile" "$TEMP_ALPINE_SERVICE" 'pidfile="/run/socks5-node/sockd.pid"'
assert_contains "Alpine service init creates logfile and runtime directory" "$TEMP_ALPINE_SERVICE" 'checkpath -f -m 0644 -o root:root "/var/log/socks5-node.log"'

assert_contains "Alpine firewall init uses openrc-run shebang" "$TEMP_ALPINE_FIREWALL_INIT" "#!/sbin/openrc-run"
assert_contains "Alpine firewall init calls helper add" "$TEMP_ALPINE_FIREWALL_INIT" '/usr/local/sbin/socks5-node-firewall add'
assert_contains "Alpine firewall init calls helper remove" "$TEMP_ALPINE_FIREWALL_INIT" '/usr/local/sbin/socks5-node-firewall remove'

assert_contains "Alpine Dante config logs to file" "$TEMP_ALPINE_CONFIG" "logoutput: syslog stderr /var/log/socks5-node.log"
assert_contains "Alpine Dante config binds high port" "$TEMP_ALPINE_CONFIG" "internal: 0.0.0.0 port = 45678"
assert_contains "Alpine Dante config matches destinations of both address families" "$TEMP_ALPINE_CONFIG" "from: 203.0.113.8/32 to: 0/0"
assert_contains "Alpine Dante config blocks IPv6 loopback" "$TEMP_ALPINE_CONFIG" "to: ::1/128"
assert_contains "Alpine default egress restricts Dante to IPv4" "$TEMP_ALPINE_CONFIG" "external.protocol: ipv4"
assert_line_order "Alpine protocol keyword precedes the external interface" \
    "$TEMP_ALPINE_CONFIG" '^external[.]protocol:' '^external:'
assert_not_contains "Alpine --dual-stack keeps both address families" "$TEMP_ALPINE_CONFIG_DUAL" "external.protocol:"
assert_contains "Alpine --dual-stack still egresses via the detected interface" "$TEMP_ALPINE_CONFIG_DUAL" "external: eth0"

# Test CLI args and environment port parsing
(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    parse_args -p 35678 -H nat.example.com
    [[ "$CLI_PORT" == "35678" && "$CLI_HOST" == "nat.example.com" && "$CONFIG_OVERRIDES" -eq 1 ]]
) || fail "parse_args handles CLI -H flag"
pass "parse_args handles CLI -H flag"

(
    export SOCKS5_NODE_LIB_ONLY=1
    export PORT=35679
    export HOST=node1.domain.com
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    parse_args
    [[ "$CLI_PORT" == "35679" && "$CLI_HOST" == "node1.domain.com" && "$CONFIG_OVERRIDES" -eq 1 ]]
) || fail "parse_args handles HOST environment variable"
pass "parse_args handles HOST environment variable"

(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$ALPINESCRIPT_PATH"
    parse_args --port 35680 --host 198.51.100.25
    [[ "$CLI_PORT" == "35680" && "$CLI_HOST" == "198.51.100.25" && "$CONFIG_OVERRIDES" -eq 1 ]]
) || fail "Alpine parse_args handles CLI --host flag"
pass "Alpine parse_args handles CLI --host flag"

(
    export SOCKS5_NODE_LIB_ONLY=1
    export PORT=35681
    export PUBLIC_HOST=alpine-nat.example.org
    # shellcheck disable=SC1090
    source "$ALPINESCRIPT_PATH"
    parse_args
    [[ "$CLI_PORT" == "35681" && "$CLI_HOST" == "alpine-nat.example.org" && "$CONFIG_OVERRIDES" -eq 1 ]]
) || fail "Alpine parse_args handles PUBLIC_HOST environment variable"
pass "Alpine parse_args handles PUBLIC_HOST environment variable"

# Test state round-trip with PUBLIC_HOST
(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$ALPINESCRIPT_PATH"
    export STATE_FILE=$TEMP_ALPINE_STATE
    export SOCKS_PORT=45678
    export SOCKS_USERNAME=s5u_deadbeef
    export SOCKS_PASSWORD=abcdef0123456789abcdef01
    export PUBLIC_HOST=nat.alpine.net
    export ALLOW_CIDR=0.0.0.0/0
    export ALLOW_PRIVATE=0
    export EXTERNAL_INTERFACE=eth0
    export DANTE_BIN=/usr/sbin/sockd
    export FIREWALL_BACKEND=none
    export FIREWALL_ZONE=""
    export AUTH_GROUP=s5g_deadbeef
    export AUTH_GROUP_GID=991
    export AUTH_USER_UID=992
    export DAEMON_USER=s5d_deadbeef
    export DAEMON_USER_UID=993
    export DAEMON_GROUP=s5d_deadbeef
    export DAEMON_GROUP_GID=994
    export INSTALLED_AT=2026-08-10T00:00:00Z
    export DANTE_WAS_PRESENT=0
    export DANTE_CONFIG_DIR_CREATED=1
    export SELINUX_ENABLED=0
    export SELINUX_PORT_MANAGED=0
    render_state >"$TEMP_ALPINE_STATE"
    load_state
    [[ "$PUBLIC_HOST" == "nat.alpine.net" ]]
) || fail "Alpine state round-trip preserves PUBLIC_HOST"
pass "Alpine state round-trip preserves PUBLIC_HOST"

(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    parse_args --force
    [[ "$CLI_FORCE" -eq 1 ]]
) || fail "parse_args handles --force flag"
pass "parse_args handles --force flag"

(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$ALPINESCRIPT_PATH"
    parse_args --reinstall
    [[ "$CLI_FORCE" -eq 1 ]]
) || fail "Alpine parse_args handles --reinstall flag"
pass "Alpine parse_args handles --reinstall flag"

rm -f -- "$TEMP_ALPINE_SERVICE" "$TEMP_ALPINE_FIREWALL_INIT" "$TEMP_ALPINE_CONFIG" "$TEMP_ALPINE_CONFIG_DUAL" "$TEMP_ALPINE_STATE"

(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    parse_args --dual-stack
    [[ "$CLI_DUAL_STACK" -eq 1 && "$CONFIG_OVERRIDES" -eq 1 ]]
) || fail "parse_args handles --dual-stack flag"
pass "parse_args handles --dual-stack flag"

(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$SCRIPT_PATH"
    parse_args
    [[ "$CLI_DUAL_STACK" -eq 0 ]]
) || fail "install defaults to IPv4-only egress"
pass "install defaults to IPv4-only egress"

(
    export SOCKS5_NODE_LIB_ONLY=1
    # shellcheck disable=SC1090
    source "$ALPINESCRIPT_PATH"
    parse_args --dual-stack
    [[ "$CLI_DUAL_STACK" -eq 1 && "$CONFIG_OVERRIDES" -eq 1 ]]
) || fail "Alpine parse_args handles --dual-stack flag"
pass "Alpine parse_args handles --dual-stack flag"

printf '1..%d\n' "$TESTS_RUN"



