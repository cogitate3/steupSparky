#!/bin/bash


# fonts color,简单快速输出颜色字
# Usage:red "字母"
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}
blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
bold(){
    echo -e "\033[1m\033[01m$1\033[0m"
}



# 安装依赖的函数
    DEPENDENCIES=(
        "curl"
        "wget"
        "git"
        "terminator"
        "bat" # 使用命令是batcat
        "python3"
        "python3-venv"
        "python3-pip"  # 添加 pip
        "pipx"
        "build-essential"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "software-properties-common"
    )

install_dependencies() {
    local dependencies=("$@")  # Accept dependencies as function arguments

    for dep in "${dependencies[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep"; then
            echo -e "${yellow}正在安装 $dep...${plain}"
            sudo apt install -y "$dep"
            if [ $? -ne 0 ]; then
                echo -e "${red}安装 $dep 失败${plain}"
                return 1
            fi
        else
            echo -e "${green}$dep 已经安装${plain}"
        fi
    done
    return 0
}

# 日志记录函数,参数分别为日志级别、消息、颜色。如果指定颜色参数为"NC"，则不遵循后面的设定的日志级别的颜色
log() {
    local level=$1
    local message=$2
    local color=$3  # 可选的颜色参数
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 根据配置文件中设置的日志级别(LOG_LEVEL)确定最低输出级别
    # case 语句类似于其他语言中的 switch 语句，用于多条件判断
    case $LOG_LEVEL in
        # 设置日志优先级：数字越小，优先级越低
        "DEBUG") log_priority=0 ;; # 调试信息：优先级最低
        "INFO")  log_priority=1 ;; # 普通信息：优先级第二低
        "WARN")  log_priority=2 ;; # 警告信息：优先级第二高
        "ERROR") log_priority=3 ;; # 错误信息：优先级最高
    esac
    
    # 根据当前日志消息的级别($level)设置对应的优先级和颜色
    case $level in
        # 如果指定了颜色为NC，则使用NC，否则根据日志级别设置默认颜色
        "DEBUG") current_priority=0; [[ $color != "NC" ]] && color=${color:-$NC} ;;    # DEBUG级别：使用默认颜色
        "INFO")  current_priority=1; [[ $color != "NC" ]] && color=${color:-$GREEN} ;; # INFO级别：使用绿色
        "WARN")  current_priority=2; [[ $color != "NC" ]] && color=${color:-$YELLOW} ;;# WARN级别：使用黄色
        "ERROR") current_priority=3; [[ $color != "NC" ]] && color=${color:-$RED} ;;   # ERROR级别：使用红色
        *)       current_priority=1; [[ $color != "NC" ]] && color=${color:-$NC} ;;    # 未知级别：默认为INFO级别和默认颜色
    esac

    # 如果指定了NC，使用NC
    [[ $color == "NC" ]] && color=$NC
    
    # 只记录优先级大于等于设置的日志级别的消息
    if [ $current_priority -ge $log_priority ]; then
        # 同时输出到控制台和日志文件
        echo -e "${color}[$timestamp] [$level] $message${NC}"
        # 写入日志文件时不包含颜色代码
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# 初始化日志文件
init_log() {
    # 创建日志目录（如果不存在）
    mkdir -p "$(dirname "$LOG_FILE")"
    # 创建日志文件（如果不存在）
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
    log "INFO" "===== 寻找最新版本的资源下载链接 脚本开始执行 ====="
    log "INFO" "系统信息: $(uname -a)"
}

# 一个函数，参数1是GitHub release页的url，目的是获得最新版本号和最新版的assets的url；参数2是url的末尾的文件特征，用于匹配适配本系统的文件
get_download_link() {
  # 检查参数
  if [ $# -ne 2 ]; then
    log "ERROR" "参数错误: 需要提供release页面的访问链接和文件特征"
    return 1
  fi

  # 获取最新版本号，并检查 curl 和 jq 的返回值
  latest_version=$(curl -s -o /dev/null -w "%{http_code}" "$1" | grep -q 200 && curl -s "$1" | jq -r '.tag_name')

  if [ $? -ne 0 ] || [ -z "$latest_version" ]; then
    log "ERROR" "无法获取最新版本号: curl 返回码 $?，版本号: $latest_version"
    return 1
  fi

  # 获取所有 assets 的下载链接，并检查 curl 和 jq 的返回值
  download_links_json=$(curl -s -o /dev/null -w "%{http_code}" "$1" | grep -q 200 && curl -s "$1" | jq -r '.assets[] | select(.name | contains("'$2'")) | .browser_download_url')

  if [ $? -ne 0 ] || [ -z "$download_links_json" ]; then
    log "ERROR" "无法获取下载链接: curl 返回码 $?，链接: $download_links_json"
    return 1
  fi

  # 输出最新版本号和下载链接
  log "INFO" "最新版本号: $latest_version"
  log "INFO" "下载链接: $download_links_json"
}


# 系统检测版本
function getLinuxOSVersion(){
    # copy from 秋水逸冰 ss scripts
    if [[ -f /etc/redhat-release ]]; then
        osRelease="centos"
        osSystemPackage="yum"
        osSystemMdPath="/usr/lib/systemd/system/"
    elif cat /etc/issue | grep -Eqi "debian"; then
        osRelease="debian"
        osSystemPackage="apt-get"
        osSystemMdPath="/lib/systemd/system/"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        osRelease="ubuntu"
        osSystemPackage="apt-get"
        osSystemMdPath="/lib/systemd/system/"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        osRelease="centos"
        osSystemPackage="yum"
        osSystemMdPath="/usr/lib/systemd/system/"
    elif cat /proc/version | grep -Eqi "debian"; then
        osRelease="debian"
        osSystemPackage="apt-get"
        osSystemMdPath="/lib/systemd/system/"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        osRelease="ubuntu"
        osSystemPackage="apt-get"
        osSystemMdPath="/lib/systemd/system/"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        osRelease="centos"
        osSystemPackage="yum"
        osSystemMdPath="/usr/lib/systemd/system/"
    fi


	if [[ -s /etc/redhat-release ]]; then
		grep -oE  "[0-9.]+" /etc/redhat-release
        osReleaseVersion=$(cat /etc/redhat-release | tr -dc '0-9.'|cut -d \. -f1)
	else
		grep -oE  "[0-9.]+" /etc/issue
        osReleaseVersion=$(cat /etc/issue | tr -dc '0-9.'|cut -d \. -f1)
	fi


    [[ -z $(echo $SHELL|grep zsh) ]] && osSystemShell="bash" || osSystemShell="zsh"

    echo "OS info: ${osRelease}, ${osReleaseVersion}, ${osSystemPackage}, ${osSystemMdPath}， ${osSystemShell}"
}

function install_micro() {
    # 安装 micro 编辑器
    if [[ ! -f "${HOME}/bin/micro" ]] ;  then
        mkdir -p ${HOME}/bin
        cd ${HOME}/bin
        curl https://getmic.ro | bash

        cp ${HOME}/bin/micro /usr/local/bin

        green " =================================================="
        yellow " micro 编辑器 安装成功!"
        green " =================================================="
    fi

}

# 菜单，用法
# start_menu "first"
# 颜色变量
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
function start_menu(){
    clear

    if [[ $1 == "first" ]] ; then
        getLinuxOSVersion
        ${osSystemPackage} -y install wget curl git 
    fi

    green " =================================================="
    green " Trojan Trojan-go V2ray 一键安装脚本 2020-12-6 更新.  系统支持：centos7+ / debian9+ / ubuntu16.04+"
    red " *请不要在任何生产环境使用此脚本 请不要有其他程序占用80和443端口"
    red " *若是已安装trojan 或第二次使用脚本，请先执行卸载trojan"
    green " =================================================="
    green " 1. 安装 老版本 BBR-PLUS 加速4合一脚本"
    green " 2. 安装 新版本 BBR-PLUS 加速6合一脚本"
    echo
    green " 3. 编辑 SSH 登录的用户公钥 用于SSH密码登录免登录"
    green " 4. 修改 SSH 登陆端口号"
    green " 5. 设置时区为北京时间"
    green " 6. 安装 Vim Nano Micro 编辑器"
    green " 7. 安装 Nodejs 与 PM2"
    green " 8. 安装 Docker 与 Docker Compose"
    echo
    green " 21. 安装 V2Ray-Poseidon 服务器端"
    green " 22. 编辑 V2Ray-Poseidon WS-TLS 模式配置文件 v2ray-poseidon/docker/v2board/ws-tls/config.json"
    green " 23. 编辑 V2Ray-Poseidon WS-TLS 模式Docker Compose文件 v2ray-poseidon/docker/v2board/ws-tls/docker-compose.yml"
    green " 24. 启动 V2Ray-Poseidon 服务器端"
    green " 25. 重启 V2Ray-Poseidon 服务器端"
    green " 26. 停止 V2Ray-Poseidon 服务器端"
    green " 27. 查看 V2Ray-Poseidon 服务器端 日志"
    green " 28. 清空 V2Ray-Poseidon Docker日志"
    red " 29. 卸载 V2Ray-Poseidon"
    echo
    green " 31. 安装 Soga 服务器端"
    green " 32. 编辑 Soga 配置文件 /etc/soga/soga.conf"
    echo
    green " 41. 单独申请域名SSL证书"
    green " 0. 退出脚本"
    echo
    read -p "请输入数字:" menuNumberInput
    case "$menuNumberInput" in
        1 )
            installBBR
        ;;
        2 )
            installBBR2
        ;;
        3 )
            editLinuxLoginWithPublicKey
        ;;
        4 )
            changeLinuxSSHPort
        ;;
        5 )
            setLinuxDateZone
        ;;
        6 )
            installSoftEditor
        ;;
        7 )
            installNodejs
        ;;
        8 )
            testLinuxPortUsage
            setLinuxDateZone
            installSoftEditor
            installDocker
        ;;
        9 )
            installPython3
        ;;
        10 )
            installPython3
            installPython3Rembg
        ;;
        21 )
            setLinuxDateZone
            installV2rayPoseidon
            getHTTPS
            replaceV2rayPoseidonConfig
        ;;
        22 )
            editV2rayPoseidonWSconfig
        ;;
        23 )
            editV2rayPoseidonDockerComposeConfig
        ;;
        24 )
            startV2rayPoseidonWS
        ;;
        25 )
            restartV2rayPoseidonWS
        ;;
        26 )
            stopV2rayPoseidonWS
        ;;
        27 )
            checkLogV2rayPoseidon
        ;;
        28 )
            deleteDockerLogs
        ;;           
        29 )
            checkLogV2rayPoseidon
        ;; 
        31 )
            setLinuxDateZone
            installSoga
            replaceSogaConfig
        ;;
        32 )
            editSogaConfig
        ;;                       
        41 )
            getHTTPS
            replaceV2rayPoseidonConfig
            replaceSogaConfig
        ;;               
        0 )
            exit 1
        ;;
        * )
            clear
            red "请输入正确数字 !"
            sleep 2s
            start_menu
        ;;
    esac

install_cheatsh() {
  apt install -y rlwrap
  curl -s https://cht.sh/:cht.sh | sudo tee /usr/local/bin/cht.sh && chmod +x /usr/local/bin/cht.sh
  echo -e "${green}cheat.sh 安装完成。 使用方法：cht.sh 命令 (例如 cht.sh curl)${plain}"
  post_installation_menu
}

# 函数：安装 angrysearch
install_angrysearch() {
    install_common_dependencies

    cd ~/Downloads
    wget https://github.com/DoTheEvo/ANGRYsearch/archive/refs/tags/v1.0.4.tar.gz
    tar -zxvf v1.0.4.tar.gz -C ~/Apps
    cd ~/Apps/ANGRYsearch-1.0.4
    sudo ./install.sh
    echo -e "${green}angrysearch 安装完成。${plain}"
    post_installation_menu
}

# 函数：安装 WPS Office (注意版本号可能需要更新)
install_wps() {
  cd ~/Downloads
  wget https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2019/11664/wps-office_11.1.0.11664_amd64.deb
  sudo dpkg -i wps-office_11.1.0.11664_amd64.deb
  sudo apt-mark hold wps-office  # 阻止 WPS 自动更新
  echo -e "${green}WPS Office 安装完成。  已阻止自动更新，请手动更新到稳定版本。${plain}"
  post_installation_menu
}

get_download_link "https://github.com/zyedidia/micro/releases" .*linux64\.tar\.gz$ .*linux64\.tar\.gz$
# 函数：安装 micro 编辑器
install_micro() {
    # 检查是否已安装 micro
    if command -v micro &> /dev/null; then
        echo -e "${green}micro 编辑器已安装。${plain}"
        post_installation_menu
        return 0
    fi

    # 创建临时下载目录
    mkdir -p ~/Downloads/micro_install

    # 下载最新版本的 micro
    echo -e "${yellow}正在下载 micro 编辑器...${plain}"
    if ! curl -L https://github.com/zyedidia/micro/releases/latest/download/micro-linux64.tar.gz -o ~/Downloads/micro_install/micro.tar.gz; then
        echo -e "${red}下载 micro 失败。请检查网络连接。${plain}"
        post_installation_menu
        return 1
    fi

    # 解压并安装
    echo -e "${yellow}正在安装 micro 编辑器...${plain}"
    tar -xzf ~/Downloads/micro_install/micro.tar.gz -C ~/Downloads/micro_install

    # 移动到系统路径
    sudo mv ~/Downloads/micro_install/micro-*/micro /usr/local/bin/

    # 清理临时文件
    rm -rf ~/Downloads/micro_install

    # 验证安装
    if command -v micro &> /dev/null; then
        echo -e "${green}micro 编辑器安装成功！${plain}"
        micro --version
    else
        echo -e "${red}micro 编辑器安装失败。${plain}"
        post_installation_menu
        return 1
    fi

    post_installation_menu
}


# 函数：安装 Plank 快捷启动器
install_plank() {
  apt update && apt install -y plank
  echo -e "${green}Plank 快捷启动器安装完成。${plain}"
  post_installation_menu
}

# 函数：安装 eggs (Debian/Ubuntu 系统工具)
install_eggs() {
    # 检查是否已安装 eggs
    if command -v eggs &> /dev/null; then
        echo -e "${green}eggs 已安装。${plain}"
        post_installation_menu
        return 0
    fi

    # 添加 GPG 密钥和仓库
    echo -e "${yellow}正在添加 eggs 仓库...${plain}"
    
    # 安装必要的依赖
    sudo apt update
    sudo apt install -y gnupg curl

    # 添加 eggs 官方仓库 GPG 密钥
    curl -fsSL https://pieroproietti.github.io/penguins-eggs/KEY.gpg | sudo gpg --dearmor -o /usr/share/keyrings/eggs-archive-keyring.gpg

    # 添加仓库源
    echo "deb [signed-by=/usr/share/keyrings/eggs-archive-keyring.gpg] https://pieroproietti.github.io/penguins-eggs/ stable main" | sudo tee /etc/apt/sources.list.d/eggs.list

    # 更新并安装 eggs
    sudo apt update
    if ! sudo apt install -y eggs; then
        echo -e "${red}eggs 安装失败。请检查网络连接和系统权限。${plain}"
        post_installation_menu
        return 1
    fi

    # 验证安装
    if command -v eggs &> /dev/null; then
        echo -e "${green}eggs 安装成功！${plain}"
        eggs --version
    else
        echo -e "${red}eggs 安装失败。${plain}"
        post_installation_menu
        return 1
    fi

    post_installation_menu
}

#13. 安装micro软件
install_micro() {
    # 检查是否已经安装了micro
    if dpkg -l | grep -q "^ii\s*micro"; then
        # 获取本地版本
        local_version=$(dpkg -l | grep  "^ii\s*micro" | awk '{print $3}')
        log 1 "micro已安装，本地版本: $local_version"
        
        # 获取远程最新版本
        get_download_link "https://github.com/zyedidia/micro/releases"
        # 从LATEST_VERSION中提取版本号（去掉v前缀）
        remote_version=${LATEST_VERSION#v}
        log 1 "远程最新版本: $remote_version"
        
        # 比较版本号，检查本地版本是否包含远程版本
        if [[ "$local_version" == *"$remote_version"* ]]; then
            log 1 "已经是最新版本，无需更新，返回主菜单"
            return 0
        else
            log 1 "发现新版本，开始更新..."
            micro_download_link=${DOWNLOAD_URL}
            install_package ${micro_download_link}
            # 检查上一个命令的返回值
            case $? in
                0)
                    log 1 "micro安装成功，返回主菜单"
                    return 0
                    ;;
                1)
                    log 3 "micro安装失败，返回主菜单"
                    return 1
                    ;;
                2)
                    log 2 "下载文件是压缩包，需要手动安装"
                    # 手动安装代码
                    
                    ;;
                return 1
            fi
        fi
    else
        # 获取最新的下载链接
        # 第二个参数是一个正则表达式，用于匹配下载链接，两边不要加双引号
        get_download_link "https://github.com/zyedidia/micro/releases" .*linux64\.tar\.gz$ 
        micro_download_link=${DOWNLOAD_URL}
        install_package ${micro_download_link}

    fi
}

# 为 zsh 添加 sudo 快捷键 (仅在 zsh 下生效)
if [ -n "$ZSH_VERSION" ]; then
    echo "bindkey -s '\e\e' '\C-asudo \C-e'" >> ~/.zshrc
    echo "请重新打开终端或运行 'exec zsh' 以应用更改。"
else
    echo "提示：sudo 快捷键仅在 zsh 下生效，当前 shell 不是 zsh。"
fi

# 待安装的软件列表
software_list=(
    "zsh"
    "micro"
    "plank"
    "eggs"
    "cheat.sh"
    "angrysearch"
    "WPS Office"
)
# 


# 过程函数：检查GitHub版本是否比本地版本更新
check_github_update_available() {
    local package_name="$1"      # 包名称
    local local_version="$2"     # 本地版本号
    local github_version="$3"    # GitHub上的版本号
    local skip_v="${4:-false}"   # 是否跳过版本号前的'v'，默认为false

    # 移除版本号前的'v'（如果需要）
    if [ "$skip_v" = "true" ]; then
        github_version=${github_version#v}
        local_version=${local_version#v}
    fi

    log 1 "$package_name 本地版本: $local_version"
    log 1 "$package_name GitHub版本: $github_version"

    # 如果版本号相同，不需要更新
    if [ "$local_version" = "$github_version" ]; then
        log 1 "$package_name 已是最新版本"
        return 1
    fi

    # 将版本号分割为数组
    IFS='.' read -ra local_parts <<< "$local_version"
    IFS='.' read -ra github_parts <<< "$github_version"

    # 比较版本号的每个部分
    for i in "${!local_parts[@]}"; do
        # 如果GitHub版本数组较短，则本地版本更新
        if [ -z "${github_parts[$i]}" ]; then
            log 1 "$package_name 本地版本更新"
            return 1
        fi
        
        # 比较数字部分
        if [ "${local_parts[$i]}" -lt "${github_parts[$i]}" ]; then
            log 1 "发现 $package_name 新版本"
            return 0
        elif [ "${local_parts[$i]}" -gt "${github_parts[$i]}" ]; then
            log 1 "$package_name 本地版本更新"
            return 1
        fi
    done

    # 如果GitHub版本有更多的部分，则GitHub版本更新
    if [ "${#github_parts[@]}" -gt "${#local_parts[@]}" ]; then
        log 1 "发现 $package_name 新版本"
        return 0
    fi

    log 1 "$package_name 已是最新版本"
    return 1
}