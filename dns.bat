@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ========================
:: 初始化配置
:: ========================
set "BORDER============================================================"
set "CONFIG_FILE=%~dp0dns_config.txt"

:: ========================
:: 管理员权限验证及提权
:: ========================
net session >nul 2>&1
if !errorlevel! == 0 (
    goto :ADMIN
) else (
    echo %BORDER%
    echo [信息] 正在请求管理员权限...
    echo %BORDER%
    powershell -Command "Start-Process -FilePath '%0' -Verb RunAs"
    exit /b
)

:ADMIN
:: ========================
:: 获取可用网络适配器
:: ========================
:GET_ADAPTERS
echo %BORDER%
echo 正在扫描网络适配器...
echo %BORDER%

set "ADAPTER_COUNT=0"
for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-NetAdapter | Where Status -eq 'Up' | Select -ExpandProperty Name"') do (
    set /a ADAPTER_COUNT+=1
    set "ADAPTER[!ADAPTER_COUNT!]=%%a"
    echo [!ADAPTER_COUNT!] %%a
)

if %ADAPTER_COUNT% equ 0 (
    echo %BORDER%
    echo [错误] 未检测到活动的网络适配器
    echo %BORDER%
    pause
    exit /b 2
)

:: ========================
:: 选择网络适配器
:: ========================
:SELECT_ADAPTER
echo %BORDER%
set /p "INPUT=请选择适配器编号 (1-%ADAPTER_COUNT%)："
echo %BORDER%

:: 输入验证
echo !INPUT!| findstr /r "^[1-9][0-9]*$" >nul || goto INVALID_ADAPTER
set /a SELECTION=!INPUT!
if !SELECTION! lss 1 goto INVALID_ADAPTER
if !SELECTION! gtr %ADAPTER_COUNT% goto INVALID_ADAPTER

:: 获取适配器名称
for %%i in (!SELECTION!) do set "TARGET_ADAPTER=!ADAPTER[%%i]!"

:: ========================
:: 选择 DNS 配置或切换到 DHCP 模式
:: ========================
:SELECT_DNS_OR_DHCP
echo %BORDER%
echo [1] 选择 DNS 配置
echo [2] 切换到 DHCP 模式
set /p "CHOICE=请选择操作 (1-2)："
echo %BORDER%

:: 输入验证
echo !CHOICE!| findstr /r "^[1-2]$" >nul || goto INVALID_CHOICE

if "!CHOICE!"=="1" (
    goto :LOAD_DNS_CONFIG
) else if "!CHOICE!"=="2" (
    echo %BORDER%
    echo 正在将 !TARGET_ADAPTER! 切换到 DHCP 模式...
    echo %BORDER%
    netsh interface ip set dns name="!TARGET_ADAPTER!" dhcp >nul
    if !errorlevel! neq 0 (
        echo %BORDER%
        echo [错误] 切换到 DHCP 模式失败
        echo %BORDER%
        pause
        exit /b 5
    )
    ipconfig /flushdns >nul
    echo %BORDER%
    echo 已成功切换到 DHCP 模式!
    echo %BORDER%
    pause
    exit /b 0
)

:LOAD_DNS_CONFIG
if not exist "%CONFIG_FILE%" (
    echo %BORDER%
    echo [错误] 配置文件丢失: %CONFIG_FILE%
    echo %BORDER%
    pause
    exit /b 3
)

echo %BORDER%
echo 可用 DNS 配置：
echo %BORDER%

set "DNS_COUNT=0"
for /f "tokens=1-3 delims=, " %%a in ('type "%CONFIG_FILE%"') do (
    set /a DNS_COUNT+=1
    set "DNS[!DNS_COUNT!].NAME=%%a"
    set "DNS[!DNS_COUNT!].PRIMARY=%%b"
    set "DNS[!DNS_COUNT!].SECONDARY=%%c"
    echo [!DNS_COUNT!] %%a (主:%%b 副:%%c)
)

:: ========================
:: 选择 DNS 配置
:: ========================
:SELECT_DNS
echo %BORDER%
set /p "DNS_CHOICE=请选择 DNS 配置 (1-!DNS_COUNT!)："
echo %BORDER%

:: 输入验证
echo !DNS_CHOICE!| findstr /r "^[1-9][0-9]*$" >nul || goto INVALID_DNS
set /a DNS_SELECTED=!DNS_CHOICE!
if !DNS_SELECTED! lss 1 goto INVALID_DNS
if !DNS_SELECTED! gtr !DNS_COUNT! goto INVALID_DNS

:: 获取 DNS 配置
for %%i in (!DNS_SELECTED!) do (
    set "PRIMARY_DNS=!DNS[%%i].PRIMARY!"
    set "SECONDARY_DNS=!DNS[%%i].SECONDARY!"
)

:: ========================
:: 应用 DNS 设置
:: ========================
echo %BORDER%
echo 正在应用 DNS 配置...
echo 主 DNS: !PRIMARY_DNS!
echo 副 DNS: !SECONDARY_DNS!
echo %BORDER%

:: 设置主 DNS
netsh interface ip set dns name="!TARGET_ADAPTER!" static !PRIMARY_DNS! >nul
if !errorlevel! neq 0 (
    echo %BORDER%
    echo [错误] 主 DNS 设置失败
    echo %BORDER%
    pause
    exit /b 4
)

:: 设置副 DNS
if defined SECONDARY_DNS (
    netsh interface ip add dns name="!TARGET_ADAPTER!" !SECONDARY_DNS! index=2 >nul
    if !errorlevel! neq 0 (
        echo %BORDER%
        echo [警告] 副 DNS 设置失败（主 DNS 已生效）
        echo %BORDER%
    )
)

:: 刷新 DNS 缓存
ipconfig /flushdns >nul
echo %BORDER%
echo DNS 配置完成!
echo %BORDER%
pause
exit /b 0

:: ========================
:: 错误处理模块
:: ========================
:INVALID_ADAPTER
echo %BORDER%
echo [错误] 无效的适配器编号
echo %BORDER%
goto GET_ADAPTERS

:INVALID_DNS
echo %BORDER%
echo [错误] 无效的 DNS 配置编号
echo %BORDER%
goto LOAD_DNS_CONFIG

:INVALID_CHOICE
echo %BORDER%
echo [错误] 无效的选择，请输入 1 或 2
echo %BORDER%
goto SELECT_DNS_OR_DHCP