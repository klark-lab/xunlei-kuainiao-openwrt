#!/bin/sh
# 迅雷快鸟 OpenWrt 路由器端安装脚本
# 直接在路由器上运行此脚本

set -e

echo "=========================================="
echo "  迅雷快鸟 OpenWrt 安装脚本"
echo "=========================================="
echo ""

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo "错误：请使用 root 用户运行此脚本"
    exit 1
fi

# 安装依赖
echo "[1/5] 安装依赖包..."
opkg update
for pkg in bash curl jq openssl-util; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        echo "安装 $pkg..."
        opkg install "$pkg"
    else
        echo "$pkg 已安装"
    fi
done

# util-linux 提供 flock
if ! command -v flock >/dev/null 2>&1; then
    echo "安装 util-linux..."
    opkg install util-linux
fi

echo "[2/5] 创建目录..."
mkdir -p /usr/share/xunlei-kuainiao
mkdir -p /var/lib/xunlei-kuainiao
mkdir -p /var/log/xunlei-kuainiao

echo "[3/5] 创建主脚本..."
cat > /usr/share/xunlei-kuainiao/xunlei-kuainiao.sh << 'MAINEOF'
#!/usr/bin/env bash
# 迅雷快鸟 OpenWrt 提速脚本
# 基于 OAuth/PKCE 流程
set -Eeuo pipefail
umask 077

UCI_CONFIG="xunlei-kuainiao"
STATE_FILE="${XL_STATE_FILE:-/var/lib/xunlei-kuainiao/state.json}"
DEBUG_DIR="${XL_DEBUG_DIR:-/var/log/xunlei-kuainiao/debug}"
LOG_FILE="${XL_LOG_FILE:-/var/log/xunlei-kuainiao/xunlei-kuainiao.log}"

ACCOUNT_CLIENT_ID="${XL_ACCOUNT_CLIENT_ID:-XW5SkOhLDjnOZP7J}"
SPEEDUP_CLIENT_ID="${XL_SPEEDUP_CLIENT_ID:-ZN3CT_2NLl6a5Q7n}"

XLUSER_BASE="https://xluser-ssl.xunlei.com"
TOKEN_URL="$XLUSER_BASE/v1/auth/token"
AUTHORIZE_URL="$XLUSER_BASE/v1/user/authorize"
SPEEDUP_OPEN_URL="https://speedup.xunlei.com/v1/open"

REDIRECT_URI="https://vip.xunlei.com/pages/2023/broadband-speed/m/?referfrom=k_gw"
SCOPE="profile user sso"

ACCOUNT_UA="${XL_ACCOUNT_UA:-Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36}"
SPEEDUP_UA="${XL_SPEEDUP_UA:-Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36}"

log()  { printf '[*] %s\n' "$*" >&2; echo "[*] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null || true; }
ok()   { printf '[+] %s\n' "$*" >&2; echo "[+] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null || true; }
warn() { printf '[!] %s\n' "$*" >&2; echo "[!] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null || true; }
die()  { printf '[错误] %s\n' "$*" >&2; echo "[错误] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null || true; exit 1; }

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf -- "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

new_tmp() { mktemp "$TMP_DIR/response.XXXXXX"; }

check_deps() {
    local missing=""
    for cmd in curl jq openssl; do
        command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
    done
    [[ -n "$missing" ]] && die "缺少依赖：$missing"
}

init_dirs() {
    mkdir -p "$(dirname "$STATE_FILE")" "$DEBUG_DIR" "$(dirname "$LOG_FILE")"
    chmod 700 "$(dirname "$STATE_FILE")" "$DEBUG_DIR" 2>/dev/null || true
}

state_init_empty() {
    [[ -f "$STATE_FILE" ]] || printf '{}\n' >"$STATE_FILE"
    chmod 600 "$STATE_FILE"
    jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || die "状态文件不是有效 JSON"
}

state_get() { jq -r --arg key "$1" '.[$key] // empty' "$STATE_FILE"; }

state_atomic_update() {
    local filter="$1"; shift
    local tmp
    tmp="$(mktemp "${STATE_FILE}.XXXXXX")"
    jq "$@" "$filter" "$STATE_FILE" >"$tmp" || { rm -f "$tmp"; die '更新状态文件失败'; }
    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

mask_value() {
    local value="$1" n=${#1}
    (( n <= 12 )) && printf '<已设置，长度 %d>' "$n" || printf '%s…%s（长度 %d）' "${value:0:6}" "${value:n-4:4}" "$n"
}

init_command() {
    state_init_empty
    local device_id refresh_token

    read -r -p 'x-device-id: ' device_id
    read -r -p 'x-device-sign（可留空）: ' account_device_sign
    read -r -s -p 'refresh_token: ' refresh_token
    printf '\n'

    [[ -n "$device_id" ]] || die 'x-device-id 不能为空'
    [[ -n "$refresh_token" ]] || die 'refresh_token 不能为空'

    state_atomic_update '
        .device_id = $device_id
        | .account_device_sign = $sign
        | .refresh_token = $refresh_token
        | .account_client_id = $acid
        | .speedup_client_id = $scid
    ' --arg device_id "$device_id" --arg sign "${account_device_sign:-}" \
      --arg refresh_token "$refresh_token" --arg acid "$ACCOUNT_CLIENT_ID" \
      --arg scid "$SPEEDUP_CLIENT_ID"

    uci set "$UCI_CONFIG.main.device_id=$device_id" 2>/dev/null || true
    uci set "$UCI_CONFIG.main.refresh_token=$refresh_token" 2>/dev/null || true
    uci commit "$UCI_CONFIG" 2>/dev/null || true

    ok "初始化完成"
}

status_command() {
    state_init_empty
    printf 'user_id: %s\n' "$(state_get user_id)"
    printf 'device_id: %s\n' "$(state_get device_id)"
    printf 'refresh_token: %s\n' "$( [[ -n "$(state_get refresh_token)" ]] && mask_value "$(state_get refresh_token)" || printf '<未设置>' )"
    printf '最近刷新: %s\n' "$(state_get token_saved_at)"
}

account_headers() {
    ACCOUNT_HEADERS=(
        -H 'accept: */*' -H 'accept-language: zh-CN' -H 'content-type: application/json'
        -H 'origin: https://i.xunlei.com' -H 'referer: https://i.xunlei.com/'
        -H "user-agent: $ACCOUNT_UA" -H "x-client-id: $ACCOUNT_CLIENT_ID"
        -H 'x-client-version: 1.1.13' -H "x-device-id: $1"
        -H 'x-device-model: chrome%2F150.0.0.0' -H 'x-device-name: Mobile-Chrome'
        -H 'x-net-work-type: NONE' -H 'x-os-version: Win32'
        -H 'x-platform-version: 3' -H 'x-protocol-version: 301'
        -H 'x-provider-name: NONE' -H 'x-sdk-version: 9.1.2'
    )
    [[ -n "$2" ]] && ACCOUNT_HEADERS+=( -H "x-device-sign: $2" )
}

save_debug() {
    [[ "${XL_DEBUG:-0}" == '1' ]] && { cp "$2" "$DEBUG_DIR/$1"; chmod 600 "$DEBUG_DIR/$1"; }
}

refresh_account_token() {
    local response http new_access new_refresh user_id
    response="$(new_tmp)"
    account_headers "$1" "$2"

    local body
    body="$(jq -nc --arg grant_type 'refresh_token' --arg refresh_token "$3" --arg client_id "$ACCOUNT_CLIENT_ID" \
        '{grant_type:$grant_type,refresh_token:$refresh_token,client_id:$client_id}')"

    log '1/4 刷新账号中心 Token'
    http="$(curl -sS --compressed --connect-timeout 15 --max-time 60 -o "$response" -w '%{http_code}' \
        -X POST "$TOKEN_URL" "${ACCOUNT_HEADERS[@]}" -d "$body")"

    save_debug '01-refresh.json' "$response"

    new_access="$(jq -r '.access_token // empty' "$response" 2>/dev/null || true)"
    new_refresh="$(jq -r '.refresh_token // empty' "$response" 2>/dev/null || true)"
    user_id="$(jq -r '.user_id // .sub // empty' "$response" 2>/dev/null || true)"

    [[ "$http" == 2* && -n "$new_access" && -n "$user_id" ]] || { warn "刷新失败 HTTP $http"; cat "$response" >&2; return 1; }

    [[ -n "$new_refresh" ]] || new_refresh="$3"
    local now expires_at
    now="$(date +%s)"
    expires_at="$((now + 7200))"

    state_atomic_update '.refresh_token=$rt|.account_access_token=$at|.user_id=$uid|.account_access_expires_at=($ea|tonumber)|.token_saved_at=($now|tonumber)' \
        --arg rt "$new_refresh" --arg at "$new_access" --arg uid "$user_id" --arg ea "$expires_at" --arg now "$now"

    uci set "$UCI_CONFIG.main.refresh_token=$new_refresh" 2>/dev/null || true
    uci commit "$UCI_CONFIG" 2>/dev/null || true

    ACCOUNT_ACCESS_TOKEN="$new_access"; ACCOUNT_REFRESH_TOKEN="$new_refresh"; USER_ID="$user_id"
    ok "Token 刷新成功，user_id=$USER_ID"
}

base64url_sha256() { printf '%s' "$1" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '='; }

generate_pkce() {
    CODE_VERIFIER="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')"
    CODE_CHALLENGE="$(base64url_sha256 "$CODE_VERIFIER")"
}

extract_authorization_code() {
    local code
    code="$(jq -r '[.code,.authorization_code,.data.code,.result.code,.redirect_uri,.redirect_url,.url,.location,.data.redirect_uri,.data.redirect_url,.data.url,.data.location,.result.redirect_uri,.result.redirect_url,.result.url,.result.location][]//empty' "$1" 2>/dev/null | while IFS= read -r c; do
        [[ -n "$c" && "$c" != 'null' ]] || continue
        [[ "$c" == a1.* ]] && { printf '%s' "$c"; exit 0; }
        local p; p="$(printf '%s' "$c" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')"
        [[ -n "$p" ]] && { printf '%s' "$p"; exit 0; }
    done)"
    [[ -n "$code" ]] && printf '%s' "$code" || return 1
}

get_authorization_code() {
    local response auth_code
    response="$(new_tmp)"
    generate_pkce

    log '2/4 获取 OAuth 授权码'
    local body
    body="$(jq -nc --arg cid "$SPEEDUP_CLIENT_ID" --arg uri "$REDIRECT_URI" --arg scope "$SCOPE" \
        --arg cc "$CODE_CHALLENGE" --arg state "state-$(openssl rand -hex 12)" \
        '{client_id:$cid,redirect_uri:$uri,response_type:"code",scope:$scope,state:$state,code_challenge:$cc,code_challenge_method:"S256"}')"

    local http
    http="$(curl -sS --compressed --connect-timeout 15 --max-time 60 -o "$response" -w '%{http_code}' \
        -X POST "$AUTHORIZE_URL" -H 'accept: */*' -H 'content-type: application/json' \
        -H "authorization: Bearer $1" -H "user-agent: $ACCOUNT_UA" -H "x-device-id: $2" -d "$body")"

    save_debug '02-authorize.json' "$response"

    [[ "$http" == 2* ]] || { warn "获取授权码失败 HTTP $http"; cat "$response" >&2; return 1; }

    auth_code="$(extract_authorization_code "$response")" || { warn "无法提取授权码"; cat "$response" >&2; return 1; }
    ok "获取授权码成功"
    printf '%s' "$auth_code"
}

exchange_speedup_token() {
    local response speedup_token
    response="$(new_tmp)"

    log '3/4 兑换快鸟 Token'
    local body
    body="$(jq -nc --arg code "$1" --arg cid "$SPEEDUP_CLIENT_ID" --arg uri "$REDIRECT_URI" --arg cv "$CODE_VERIFIER" \
        '{grant_type:"authorization_code",code:$code,client_id:$cid,redirect_uri:$uri,code_verifier:$cv}')"

    local http
    http="$(curl -sS --compressed --connect-timeout 15 --max-time 60 -o "$response" -w '%{http_code}' \
        -X POST "$XLUSER_BASE/v1/auth/token" -H 'accept: */*' -H 'content-type: application/json' \
        -H "user-agent: $SPEEDUP_UA" -H "x-device-id: $2" -d "$body")"

    save_debug '03-exchange.json' "$response"

    speedup_token="$(jq -r '.access_token // empty' "$response" 2>/dev/null || true)"

    [[ "$http" == 2* && -n "$speedup_token" ]] || { warn "兑换失败 HTTP $http"; cat "$response" >&2; return 1; }

    state_atomic_update '.speedup_access_token=$t' --arg t "$speedup_token"
    ok "兑换快鸟 Token 成功"
    SPEEDUP_ACCESS_TOKEN="$speedup_token"
}

activate_speedup() {
    local response
    response="$(new_tmp)"

    log '4/4 调用提速开通接口'
    local http
    http="$(curl -sS --compressed --connect-timeout 15 --max-time 60 -o "$response" -w '%{http_code}' \
        -X POST "$SPEEDUP_OPEN_URL" -H 'accept: */*' -H 'content-type: application/json' \
        -H "authorization: Bearer $1" -H "user-agent: $SPEEDUP_UA" -H "x-device-id: $2" \
        -H 'platform: web' -H 'Origin: https://vip.xunlei.com' \
        -H 'Referer: https://vip.xunlei.com/pages/2023/broadband-speed/m/?referfrom=k_gw' \
        -d '{}')"

    save_debug '04-speedup.json' "$response"

    local result
    result="$(jq -r '.ret // .code // empty' "$response" 2>/dev/null || true)"

    [[ "$http" == 2* ]] || { warn "提速请求失败 HTTP $http"; cat "$response" >&2; return 1; }

    if [[ "$result" == "0" ]]; then
        ok "提速开通成功！"
        state_atomic_update '.last_success=($n|tonumber)' --arg n "$(date +%s)"
    elif [[ "$result" == "11" ]]; then
        warn "试用额度已用完（ret=11），请明天再试"
    else
        warn "提速返回异常（ret=$result）"; cat "$response" >&2
    fi
}

run_command() {
    check_deps; init_dirs; state_init_empty

    local device_id device_sign refresh_token
    device_id="$(state_get device_id)"
    device_sign="$(state_get account_device_sign)"
    refresh_token="$(state_get refresh_token)"

    [[ -n "$device_id" ]] || die "未配置 device_id，请先运行 init"
    [[ -n "$refresh_token" ]] || die "未配置 refresh_token，请先运行 init"

    refresh_account_token "$device_id" "$device_sign" "$refresh_token" || die "刷新 Token 失败"

    local auth_code
    auth_code="$(get_authorization_code "$ACCOUNT_ACCESS_TOKEN" "$device_id")" || die "获取授权码失败"

    exchange_speedup_token "$auth_code" "$device_id" || die "兑换 Token 失败"

    activate_speedup "$SPEEDUP_ACCESS_TOKEN" "$device_id"
}

refresh_command() {
    check_deps; init_dirs; state_init_empty
    local device_id device_sign refresh_token
    device_id="$(state_get device_id)"; device_sign="$(state_get account_device_sign)"; refresh_token="$(state_get refresh_token)"
    [[ -n "$device_id" ]] || die "未配置 device_id"
    [[ -n "$refresh_token" ]] || die "未配置 refresh_token"
    refresh_account_token "$device_id" "$device_sign" "$refresh_token"
}

show_help() {
    cat <<EOF
迅雷快鸟 OpenWrt 提速工具

用法：xunlei-kuainiao-cli [命令]

命令：
  init      初始化配置
  run       执行提速
  refresh   刷新 Token
  status    查看状态
  help      帮助信息
EOF
}

main() {
    case "${1:-help}" in
        init) init_command ;;
        run) run_command ;;
        refresh) refresh_command ;;
        status) status_command ;;
        help|--help|-h) show_help ;;
        *) die "未知命令：$1" ;;
    esac
}

main "$@"
MAINEOF

chmod 755 /usr/share/xunlei-kuainiao/xunlei-kuainiao.sh

echo "[4/5] 创建 CLI 包装脚本..."
cat > /usr/bin/xunlei-kuainiao-cli << 'CLIEOF'
#!/bin/sh
if ! command -v bash >/dev/null 2>&1; then
    echo "错误：需要安装 bash，请运行：opkg install bash"
    exit 1
fi
exec bash /usr/share/xunlei-kuainiao/xunlei-kuainiao.sh "$@"
CLIEOF

chmod 755 /usr/bin/xunlei-kuainiao-cli

echo "[5/5] 创建配置文件..."
cat > /etc/config/xunlei-kuainiao << 'CONFIGEOF'
config xunlei-kuainiao 'main'
    option enabled '1'
    option device_id ''
    option refresh_token ''
    option device_sign ''
    option auto_renew '1'
    option renew_cron '15 3 * * *'
    option log_level 'info'
    option state_file '/var/lib/xunlei-kuainiao/state.json'
CONFIGEOF

cat > /etc/init.d/xunlei-kuainiao << 'INITEOF'
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

PROG=/usr/bin/xunlei-kuainiao-cli
LOG_FILE=/var/log/xunlei-kuainiao/xunlei-kuainiao.log

start_service() {
    local enabled
    config_load xunlei-kuainiao
    config_get enabled main enabled 1
    [ "$enabled" != "1" ] && return 0
    mkdir -p /var/log/xunlei-kuainiao /var/lib/xunlei-kuainiao
    $PROG run >> "$LOG_FILE" 2>&1 &
    setup_cron
}

stop_service() {
    remove_cron
}

setup_cron() {
    local auto_renew renew_cron
    config_load xunlei-kuainiao
    config_get auto_renew main auto_renew 1
    config_get renew_cron main renew_cron "15 3 * * *"
    if [ "$auto_renew" = "1" ]; then
        remove_cron
        echo "$renew_cron $PROG run >> $LOG_FILE 2>&1" >> /etc/crontabs/root
        /etc/init.d/cron restart
    fi
}

remove_cron() {
    sed -i '/xunlei-kuainiao-cli/d' /etc/crontabs/root 2>/dev/null || true
}

service_triggers() {
    procd_add_reload_trigger "xunlei-kuainiao"
}
INITEOF

chmod 755 /etc/init.d/xunlei-kuainiao

echo ""
echo "=========================================="
echo "  安装完成！"
echo "=========================================="
echo ""
echo "下一步："
echo ""
echo "1. 初始化配置（需要从浏览器获取凭据）："
echo "   xunlei-kuainiao-cli init"
echo ""
echo "2. 执行提速："
echo "   xunlei-kuainiao-cli run"
echo ""
echo "3. 启用开机自启："
echo "   /etc/init.d/xunlei-kuainiao enable"
echo "   /etc/init.d/xunlei-kuainiao start"
echo ""
