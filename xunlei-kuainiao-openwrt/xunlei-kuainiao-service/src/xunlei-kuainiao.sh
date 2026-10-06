#!/usr/bin/env bash
# 迅雷快鸟 OpenWrt 提速脚本
# 基于 OAuth/PKCE 流程，参考 Sakamakiiizayoi/xunlei-speedup-oauth
set -Eeuo pipefail
umask 077

# OpenWrt UCI 配置支持
UCI_CONFIG="xunlei-kuainiao"

# 默认配置
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

# 日志函数
log()  {
    local msg="[*] $(date '+%Y-%m-%d %H:%M:%S') $*"
    printf '%s\n' "$msg" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

ok()   {
    local msg="[+] $(date '+%Y-%m-%d %H:%M:%S') $*"
    printf '%s\n' "$msg" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    local msg="[!] $(date '+%Y-%m-%d %H:%M:%S') $*"
    printf '%s\n' "$msg" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

die() {
    local msg="[错误] $(date '+%Y-%m-%d %H:%M:%S') $*"
    printf '%s\n' "$msg" >&2
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    exit 1
}

# 从 UCI 读取配置
uci_get() {
    local option="$1"
    local default="${2:-}"
    uci -q get "$UCI_CONFIG.main.$option" 2>/dev/null || echo "$default"
}

# 从 UCI 设置配置
uci_set() {
    local option="$1"
    local value="$2"
    uci set "$UCI_CONFIG.main.$option=$value" 2>/dev/null || true
}

# 初始化 UCI 配置
init_uci_config() {
    if ! uci -q get "$UCI_CONFIG" >/dev/null 2>&1; then
        uci set "$UCI_CONFIG=service"
        uci set "$UCI_CONFIG.main=section"
        uci set "$UCI_CONFIG.main.enabled=1"
        uci set "$UCI_CONFIG.main.device_id=''"
        uci set "$UCI_CONFIG.main.refresh_token=''"
        uci set "$UCI_CONFIG.main.device_sign=''"
        uci set "$UCI_CONFIG.main.auto_renew=1"
        uci set "$UCI_CONFIG.main.renew_cron='15 3 * * *'"
        uci set "$UCI_CONFIG.main.log_level='info'"
        uci set "$UCI_CONFIG.main.state_file='/var/lib/xunlei-kuainiao/state.json'"
        uci commit "$UCI_CONFIG"
    fi
}

# 临时目录
TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf -- "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

new_tmp() {
    mktemp "$TMP_DIR/response.XXXXXX"
}

# 检查依赖
check_deps() {
    local missing=""
    for cmd in curl jq openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done
    if [[ -n "$missing" ]]; then
        die "缺少依赖：$missing，请先安装：opkg install curl jq openssl"
    fi
}

# 创建目录
init_dirs() {
    mkdir -p "$(dirname "$STATE_FILE")" "$DEBUG_DIR" "$(dirname "$LOG_FILE")"
    chmod 700 "$(dirname "$STATE_FILE")" "$DEBUG_DIR" 2>/dev/null || true
}

# 状态文件操作
state_init_empty() {
    [[ -f "$STATE_FILE" ]] || printf '{}\n' >"$STATE_FILE"
    chmod 600 "$STATE_FILE"
    jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1 || die "状态文件不是有效 JSON：$STATE_FILE"
}

state_get() {
    local key="$1"
    jq -r --arg key "$key" '.[$key] // empty' "$STATE_FILE"
}

state_atomic_update() {
    local filter="$1"
    shift
    local tmp
    tmp="$(mktemp "${STATE_FILE}.XXXXXX")"
    if ! jq "$@" "$filter" "$STATE_FILE" >"$tmp"; then
        rm -f "$tmp"
        die '更新状态文件失败'
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

mask_value() {
    local value="$1" n=${#1}
    if (( n <= 12 )); then
        printf '<已设置，长度 %d>' "$n"
    else
        printf '%s…%s（长度 %d）' "${value:0:6}" "${value:n-4:4}" "$n"
    fi
}

# 初始化命令
init_command() {
    state_init_empty
    init_uci_config

    local device_id account_device_sign refresh_token

    # 从 UCI 或环境变量读取
    device_id="${XL_DEVICE_ID:-$(uci_get device_id)}"
    account_device_sign="${XL_ACCOUNT_DEVICE_SIGN:-$(uci_get device_sign)}"
    refresh_token="${XL_ACCOUNT_REFRESH_TOKEN:-$(uci_get refresh_token)}"

    if [[ -z "$device_id" ]]; then
        read -r -p '账号中心请求中的 x-device-id：' device_id
    else
        printf '账号中心 x-device-id [%s]：' "$device_id"
        local input=''
        read -r input
        [[ -z "$input" ]] || device_id="$input"
    fi

    if [[ -z "$account_device_sign" ]]; then
        read -r -p '账号中心请求中的 x-device-sign（可留空尝试）：' account_device_sign
    else
        printf '账号中心 x-device-sign 已存在，直接回车保留；输入新值覆盖：'
        local sign_input=''
        read -r sign_input
        [[ -z "$sign_input" ]] || account_device_sign="$sign_input"
    fi

    if [[ -z "$refresh_token" ]]; then
        read -r -s -p 'credentials_XW5SkOhLDjnOZP7J 中最新的 refresh_token：' refresh_token
        printf '\n'
    fi

    [[ -n "$device_id" ]] || die 'x-device-id 不能为空'
    [[ -n "$refresh_token" ]] || die 'refresh_token 不能为空'

    # 保存到状态文件
    state_atomic_update '
        .device_id = $device_id
        | .account_device_sign = $account_device_sign
        | .refresh_token = $refresh_token
        | .account_client_id = $account_client_id
        | .speedup_client_id = $speedup_client_id
    ' \
        --arg device_id "$device_id" \
        --arg account_device_sign "$account_device_sign" \
        --arg refresh_token "$refresh_token" \
        --arg account_client_id "$ACCOUNT_CLIENT_ID" \
        --arg speedup_client_id "$SPEEDUP_CLIENT_ID"

    # 保存到 UCI
    uci_set device_id "$device_id"
    uci_set device_sign "$account_device_sign"
    uci_set refresh_token "$refresh_token"
    uci commit "$UCI_CONFIG"

    ok "初始化完成：$STATE_FILE"
    warn 'refresh_token 会轮换；以后以状态文件中的新值为准，不要再使用旧值。'
}

# 状态查看命令
status_command() {
    state_init_empty
    local device_id sign refresh user_id saved_at
    device_id="$(state_get device_id)"
    sign="$(state_get account_device_sign)"
    refresh="$(state_get refresh_token)"
    user_id="$(state_get user_id)"
    saved_at="$(state_get token_saved_at)"

    printf '状态文件：%s\n' "$STATE_FILE"
    printf 'user_id：%s\n' "${user_id:-<未知>}"
    printf 'device_id：%s\n' "${device_id:-<未设置>}"
    printf 'device_sign：%s\n' "$( [[ -n "$sign" ]] && mask_value "$sign" || printf '<未设置>' )"
    printf 'refresh_token：%s\n' "$( [[ -n "$refresh" ]] && mask_value "$refresh" || printf '<未设置>' )"
    printf '最近刷新时间戳：%s\n' "${saved_at:-<无>}"
}

# 账号中心请求头
account_headers() {
    local device_id="$1"
    local device_sign="$2"

    ACCOUNT_HEADERS=(
        -H 'accept: */*'
        -H 'accept-language: zh-CN'
        -H 'content-type: application/json'
        -H 'origin: https://i.xunlei.com'
        -H 'referer: https://i.xunlei.com/'
        -H "user-agent: $ACCOUNT_UA"
        -H "x-client-id: $ACCOUNT_CLIENT_ID"
        -H 'x-client-version: 1.1.13'
        -H "x-device-id: $device_id"
        -H 'x-device-model: chrome%2F150.0.0.0'
        -H 'x-device-name: Mobile-Chrome'
        -H 'x-net-work-type: NONE'
        -H 'x-os-version: Win32'
        -H 'x-platform-version: 3'
        -H 'x-protocol-version: 301'
        -H 'x-provider-name: NONE'
        -H 'x-sdk-version: 9.1.2'
    )
    [[ -z "$device_sign" ]] || ACCOUNT_HEADERS+=( -H "x-device-sign: $device_sign" )
}

pretty_or_cat() {
    local file="$1"
    jq . "$file" 2>/dev/null || cat "$file"
}

save_debug() {
    local name="$1" file="$2"
    if [[ "${XL_DEBUG:-0}" == '1' ]]; then
        cp "$file" "$DEBUG_DIR/$name"
        chmod 600 "$DEBUG_DIR/$name"
        warn "已保存调试响应：$DEBUG_DIR/$name"
    fi
}

# 刷新账号中心 Token
refresh_account_token() {
    local device_id="$1"
    local device_sign="$2"
    local account_refresh_token="$3"

    local body response http new_access new_refresh user_id expires_in expires_at now
    response="$(new_tmp)"

    account_headers "$device_id" "$device_sign"

    body="$(jq -nc \
        --arg grant_type 'refresh_token' \
        --arg refresh_token "$account_refresh_token" \
        --arg client_id "$ACCOUNT_CLIENT_ID" \
        '{grant_type:$grant_type,refresh_token:$refresh_token,client_id:$client_id}')"

    log '1/4 刷新迅雷账号中心 Token'
    http="$(curl --silent --show-error --compressed \
        --connect-timeout 15 --max-time 60 \
        --output "$response" --write-out '%{http_code}' \
        --request POST "$TOKEN_URL" \
        "${ACCOUNT_HEADERS[@]}" \
        --data-raw "$body")"

    save_debug '01-refresh.json' "$response"

    new_access="$(jq -r '.access_token // empty' "$response" 2>/dev/null || true)"
    new_refresh="$(jq -r '.refresh_token // empty' "$response" 2>/dev/null || true)"
    user_id="$(jq -r '.user_id // .sub // empty' "$response" 2>/dev/null || true)"
    expires_in="$(jq -r '.expires_in // 7200' "$response" 2>/dev/null || printf '7200')"

    if [[ "$http" != 2* || -z "$new_access" || -z "$user_id" ]]; then
        warn "账号中心 Token 刷新失败（HTTP $http）"
        pretty_or_cat "$response" >&2
        return 1
    fi

    # 服务器会轮换 refresh_token。必须在后续网络步骤之前立即原子保存。
    [[ -n "$new_refresh" ]] || new_refresh="$account_refresh_token"
    now="$(date +%s)"
    expires_at="$((now + expires_in))"

    state_atomic_update '
        .refresh_token = $refresh_token
        | .account_access_token = $access_token
        | .user_id = $user_id
        | .account_access_expires_at = ($expires_at | tonumber)
        | .token_saved_at = ($saved_at | tonumber)
    ' \
        --arg refresh_token "$new_refresh" \
        --arg access_token "$new_access" \
        --arg user_id "$user_id" \
        --arg expires_at "$expires_at" \
        --arg saved_at "$now"

    # 同步到 UCI
    uci_set refresh_token "$new_refresh"
    uci commit "$UCI_CONFIG"

    ACCOUNT_ACCESS_TOKEN="$new_access"
    ACCOUNT_REFRESH_TOKEN="$new_refresh"
    USER_ID="$user_id"
    ok "账号中心 Token 刷新成功，user_id=$USER_ID；新 refresh_token 已落盘"
}

# 生成 PKCE 参数
base64url_sha256() {
    printf '%s' "$1" \
        | openssl dgst -sha256 -binary \
        | openssl base64 -A \
        | tr '+/' '-_' \
        | tr -d '='
}

generate_pkce() {
    CODE_VERIFIER="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')"
    CODE_CHALLENGE="$(base64url_sha256 "$CODE_VERIFIER")"
    OAUTH_STATE="state-$(openssl rand -hex 12)"
}

# 提取授权码
extract_authorization_code() {
    local file="$1" candidate code

    while IFS= read -r candidate; do
        [[ -n "$candidate" && "$candidate" != 'null' ]] || continue

        if [[ "$candidate" == a1.* ]]; then
            printf '%s' "$candidate"
            return 0
        fi

        code="$(printf '%s' "$candidate" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')"
        if [[ -n "$code" ]]; then
            printf '%s' "$code"
            return 0
        fi
    done < <(
        jq -r '
            [
                .code,
                .authorization_code,
                .data.code,
                .result.code,
                .redirect_uri,
                .redirect_url,
                .url,
                .location,
                .data.redirect_uri,
                .data.redirect_url,
                .data.url,
                .data.location,
                .result.redirect_uri,
                .result.redirect_url,
                .result.url,
                .result.location
            ][] // empty
        ' "$file" 2>/dev/null
    )
    return 1
}

# 获取 OAuth 授权码
get_authorization_code() {
    local account_access_token="$1"
    local device_id="$2"

    local response http auth_code
    response="$(new_tmp)"

    log '2/4 获取快鸟 OAuth 授权码'

    generate_pkce

    local authorize_body
    authorize_body="$(jq -nc \
        --arg client_id "$SPEEDUP_CLIENT_ID" \
        --arg redirect_uri "$REDIRECT_URI" \
        --arg response_type 'code' \
        --arg scope "$SCOPE" \
        --arg state "$OAUTH_STATE" \
        --arg code_challenge "$CODE_CHALLENGE" \
        --arg code_challenge_method 'S256' \
        '{
            client_id: $client_id,
            redirect_uri: $redirect_uri,
            response_type: $response_type,
            scope: $scope,
            state: $state,
            code_challenge: $code_challenge,
            code_challenge_method: $code_challenge_method
        }')"

    http="$(curl --silent --show-error --compressed \
        --connect-timeout 15 --max-time 60 \
        --output "$response" --write-out '%{http_code}' \
        --request POST "$AUTHORIZE_URL" \
        -H 'accept: */*' \
        -H 'accept-language: zh-CN' \
        -H 'content-type: application/json' \
        -H "authorization: Bearer $account_access_token" \
        -H "user-agent: $ACCOUNT_UA" \
        -H "x-device-id: $device_id" \
        --data-raw "$authorize_body")"

    save_debug '02-authorize.json' "$response"

    if [[ "$http" != 2* ]]; then
        warn "获取授权码失败（HTTP $http）"
        pretty_or_cat "$response" >&2
        return 1
    fi

    auth_code="$(extract_authorization_code "$response")"
    if [[ -z "$auth_code" ]]; then
        warn "无法从响应中提取授权码"
        pretty_or_cat "$response" >&2
        return 1
    fi

    ok "获取授权码成功"
    printf '%s' "$auth_code"
}

# 兑换快鸟 Access Token
exchange_speedup_token() {
    local auth_code="$1"
    local device_id="$2"

    local response http speedup_access_token
    response="$(new_tmp)"

    log '3/4 兑换快鸟 Access Token'

    local token_body
    token_body="$(jq -nc \
        --arg grant_type 'authorization_code' \
        --arg code "$auth_code" \
        --arg client_id "$SPEEDUP_CLIENT_ID" \
        --arg redirect_uri "$REDIRECT_URI" \
        --arg code_verifier "$CODE_VERIFIER" \
        '{
            grant_type: $grant_type,
            code: $code,
            client_id: $client_id,
            redirect_uri: $redirect_uri,
            code_verifier: $code_verifier
        }')"

    local token_url="$XLUSER_BASE/v1/auth/token"

    http="$(curl --silent --show-error --compressed \
        --connect-timeout 15 --max-time 60 \
        --output "$response" --write-out '%{http_code}' \
        --request POST "$token_url" \
        -H 'accept: */*' \
        -H 'accept-language: zh-CN' \
        -H 'content-type: application/json' \
        -H "user-agent: $SPEEDUP_UA" \
        -H "x-device-id: $device_id" \
        --data-raw "$token_body")"

    save_debug '03-exchange.json' "$response"

    speedup_access_token="$(jq -r '.access_token // empty' "$response" 2>/dev/null || true)"

    if [[ "$http" != 2* || -z "$speedup_access_token" ]]; then
        warn "兑换快鸟 Token 失败（HTTP $http）"
        pretty_or_cat "$response" >&2
        return 1
    fi

    state_atomic_update '
        .speedup_access_token = $token
    ' --arg token "$speedup_access_token"

    ok "兑换快鸟 Token 成功"
    SPEEDUP_ACCESS_TOKEN="$speedup_access_token"
}

# 调用提速开通接口
activate_speedup() {
    local speedup_access_token="$1"
    local device_id="$2"

    local response http result
    response="$(new_tmp)"

    log '4/4 调用快鸟提速开通接口'

    http="$(curl --silent --show-error --compressed \
        --connect-timeout 15 --max-time 60 \
        --output "$response" --write-out '%{http_code}' \
        --request POST "$SPEEDUP_OPEN_URL" \
        -H 'accept: */*' \
        -H 'accept-language: zh-CN' \
        -H 'content-type: application/json' \
        -H "authorization: Bearer $speedup_access_token" \
        -H "user-agent: $SPEEDUP_UA" \
        -H "x-device-id: $device_id" \
        -H 'platform: web' \
        -H 'Origin: https://vip.xunlei.com' \
        -H 'Referer: https://vip.xunlei.com/pages/2023/broadband-speed/m/?referfrom=k_gw' \
        --data-raw '{}')"

    save_debug '04-speedup.json' "$response"

    result="$(jq -r '.ret // .code // empty' "$response" 2>/dev/null || true)"

    if [[ "$http" != 2* ]]; then
        warn "提速开通请求失败（HTTP $http）"
        pretty_or_cat "$response" >&2
        return 1
    fi

    if [[ "$result" == "0" ]]; then
        ok "提速开通成功！"
        state_atomic_update '
            .last_success = ($now | tonumber)
        ' --arg now "$(date +%s)"
    elif [[ "$result" == "11" ]]; then
        warn "试用额度已用完（ret=11），请明天再试或升级 VIP"
    else
        warn "提速开通返回异常（ret=$result）"
        pretty_or_cat "$response" >&2
    fi
}

# 完整执行流程
run_command() {
    check_deps
    init_dirs
    state_init_empty

    local device_id device_sign refresh_token

    device_id="$(state_get device_id)"
    device_sign="$(state_get account_device_sign)"
    refresh_token="$(state_get refresh_token)"

    [[ -n "$device_id" ]] || die "未配置 device_id，请先运行：xunlei-kuainiao-cli init"
    [[ -n "$refresh_token" ]] || die "未配置 refresh_token，请先运行：xunlei-kuainiao-cli init"

    # 1. 刷新账号中心 Token
    refresh_account_token "$device_id" "$device_sign" "$refresh_token" || die "刷新 Token 失败"

    # 2. 获取 OAuth 授权码
    local auth_code
    auth_code="$(get_authorization_code "$ACCOUNT_ACCESS_TOKEN" "$device_id")" || die "获取授权码失败"

    # 3. 兑换快鸟 Token
    exchange_speedup_token "$auth_code" "$device_id" || die "兑换快鸟 Token 失败"

    # 4. 调用提速开通
    activate_speedup "$SPEEDUP_ACCESS_TOKEN" "$device_id" || die "提速开通失败"
}

# 只刷新 Token
refresh_command() {
    check_deps
    init_dirs
    state_init_empty

    local device_id device_sign refresh_token

    device_id="$(state_get device_id)"
    device_sign="$(state_get account_device_sign)"
    refresh_token="$(state_get refresh_token)"

    [[ -n "$device_id" ]] || die "未配置 device_id，请先运行：xunlei-kuainiao-cli init"
    [[ -n "$refresh_token" ]] || die "未配置 refresh_token，请先运行：xunlei-kuainiao-cli init"

    refresh_account_token "$device_id" "$device_sign" "$refresh_token"
}

# 显示帮助
show_help() {
    cat <<EOF
迅雷快鸟 OpenWrt 提速工具

用法：
    xunlei-kuainiao-cli [命令]

命令：
    init        初始化配置（首次使用）
    run         执行完整提速流程
    refresh     只刷新账号中心 Token
    status      查看当前状态
    help        显示此帮助信息

环境变量：
    XL_STATE_FILE       自定义状态文件路径
    XL_DEBUG_DIR        自定义调试响应目录
    XL_DEBUG=1          保存各步骤响应

配置文件：
    /etc/config/xunlei-kuainiao

状态文件：
    /var/lib/xunlei-kuainiao/state.json

日志文件：
    /var/log/xunlei-kuainiao/xunlei-kuainiao.log
EOF
}

# 主入口
main() {
    local command="${1:-help}"

    case "$command" in
        init)
            init_command
            ;;
        run)
            run_command
            ;;
        refresh)
            refresh_command
            ;;
        status)
            status_command
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            die "未知命令：$command，使用 help 查看帮助"
            ;;
    esac
}

main "$@"
