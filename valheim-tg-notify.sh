#!/bin/bash
# Определяем путь к директории скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/valheim-tg-notify.conf"
MESSAGES_FILE="${SCRIPT_DIR}/messages.conf"
USERLIST="${SCRIPT_DIR}/usernames.txt"
# Функция для логирования с временной меткой
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1"
}

# --- Добавлена функция urlencode ---
# Простая функция для URL-кодирования строки
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [a-zA-Z0-9.~_-]) o="${c}" ;;
            *) printf -v o '%%%02x' "'$c" ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Функция для экранирования специальных символов HTML
html_encode() {
    local string="$1"
    # Экранируем & < > " '
    string="${string//&/&amp;}"
    string="${string//</<}"
    string="${string//>/>}"
    string="${string//\"/&quot;}"
    string="${string//\'/&apos;}"
    # Экранируем скобки, если они не являются частью тегов (для безопасности, хотя < > уже должны помочь)
    # string="${string//(/&#40;}"
    # string="${string//)/&#41;}"
    echo "$string"
}

# Функция создания конфигурационного файла по умолчанию
create_default_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
# Настройки скрипта:
TIMEOUT="10"
LOGFILE="/valheim_server/logs/valheim.log"
# Раскомментируйте стрроку ниже, чтобы указать свой путь к файлу с ассоциациями SteamID Nickname, если в папке со скриптом нет доступа на запись.
#USERLIST="/path/to/your/custom/usernames.txt"
# Настройка токена Telegram-бота, полученного у @BotFather:
KEY="1111111:Telegram_Bot-Token"
# Укажите ID чата в телеграме. Узнать ID можно, например, отправив боту @username_to_id_bot ссылку на ваш чат:
CHATID="-1111111111111"
# Ниже заполнить только если формат чата с темами. Если чат единый, то оставить пустым.
# Узнать id темы можно в ссылке в шапке темы.
# Например: https://t.me/chatname/1     - где 1 - это id темы
THREAD_ID=""
EOF
        log_message "Создан файл конфигурации по умолчанию: $CONFIG_FILE"
        log_message "!!! ВАЖНО: Необходимо настроить файл valheim-tg-notify.conf перед использованием скрипта !!!"
        return 1 # Возвращаем код ошибки, чтобы скрипт завершился
    fi
    return 0 # Файл существует
}
# Функция загрузки конфигурации
load_config() {
    if [[ -f "$CONFIG_FILE" && -r "$CONFIG_FILE" ]]; then
        # Безопасно загружаем конфигурацию из файла
        source "$CONFIG_FILE"
        log_message "Конфигурация загружена из: $CONFIG_FILE"
    else
        log_message "Ошибка: Файл конфигурации $CONFIG_FILE не найден или недоступен для чтения"
        exit 1
    fi
}
# Функция загрузки сообщений
load_messages() {
    if [[ -f "$MESSAGES_FILE" && -r "$MESSAGES_FILE" ]]; then
        source "$MESSAGES_FILE"
        log_message "Сообщения загружены из: $MESSAGES_FILE"
    else
        log_message "Предупреждение: Файл сообщений $MESSAGES_FILE не найден, будут использованы значения по умолчанию"
    fi
}
# Проверяем и создаем конфиг по умолчанию при необходимости
if ! create_default_config; then
    exit 1
fi
# Загружаем конфигурацию и сообщения
load_config
load_messages
# Формируем URL для API Telegram после загрузки конфигурации
URL="https://api.telegram.org/bot${KEY}/sendMessage"
# Переменные, не требующие конфигурации
STEAMURL="https://steamcommunity.com/profiles/"
VALHEIMVERSION="Not set"
CHECK_INTERVAL=300
# Функция отправки сообщения в Telegram
send(){
    # --- Изменена функция send для использования HTML ---
    local message_text_template="$1"
    local substituted_text
    # Используем envsubst для подстановки переменных
    substituted_text=$(echo -e "$message_text_template" | envsubst)

    # Экранируем специальные символы HTML в подставленном тексте
    local safe_text
    safe_text=$(html_encode "$substituted_text")

    # URL-кодируем текст сообщения для передачи через curl
    local encoded_text
    encoded_text=$(urlencode "$safe_text")

    # Формируем данные для POST-запроса с parse_mode=HTML
    local data="chat_id=$CHATID&disable_web_page_preview=1&parse_mode=HTML&text=$encoded_text"
    # Добавляем ID темы, если он задан
    if [ -n "$THREAD_ID" ]; then
        data="$data&message_thread_id=$THREAD_ID"
    fi
    # Логируем отправку сообщения (до кодирования, чтобы было читаемо)
    log_message "Отправка в Telegram (HTML): $substituted_text"
    # Отправляем POST-запрос на API Telegram и подавляем вывод
    curl -s --max-time $TIMEOUT -X POST -d "$data" "$URL" > /dev/null 2>&1 || log_message "Ошибка при отправке сообщения в Telegram"
    # --- Конец изменений в функции send ---
}
# Функция добавления имени игрока по его SteamID в файл USERLIST
addcharname(){
    # Пытаемся получить имя профиля Steam с помощью cURL и парсинга HTML
    NAME=$(curl -sL --max-time $TIMEOUT "$STEAMURL$1" 2>/dev/null | grep -oPm1 'actual_persona_name">\K(.+)(?=</span>)')
    # Если имя найдено, добавляем связку SteamID + имя в файл и перезагружаем кэш
    if [[ -n "$NAME" ]]; then
        echo "$1 $NAME" >> "$USERLIST"
        log_message "Добавлен новый игрок: $1 $NAME"
        loadnames
    else
        log_message "Не удалось получить имя для SteamID: $1"
    fi
}
# Функция получения имени игрока по SteamID из ассоциативного массива
charname(){
    # Проверяем, существует ли такой ключ (SteamID) в массиве USERNAMES
    if [[ -n "$1" && ${USERNAMES[$1]+abc} ]]; then
        echo "${USERNAMES[$1]}" # Если да, возвращаем имя
    else
        echo "Unknown ($1)" # Если нет, возвращаем "Unknown" и SteamID
    fi
}
# Функция загрузки SteamID и имен игроков из файла в ассоциативный массив USERNAMES
loadnames(){
    declare -gA USERNAMES # Объявляем ассоциативный массив (глобальный)
    # Создаем файл usernames.txt, если он не существует
    if ! [[ -f "$USERLIST" ]]; then
        log_message "Создание файла $USERLIST"
        cat > "$USERLIST" << 'EOF'
# Формат: SteamID Имя_игрока
EOF
        log_message "Файл $USERLIST создан"
    fi
    if ! [[ -r "$USERLIST" ]]; then
        log_message "Внимание: не удалось прочитать $USERLIST" # Предупреждение, если файл недоступен
    else
        # Читаем файл построчно, игнорируем комментарии и пустые строки
        while IFS= read -r line; do
            if ! [[ $line == "#"* || $line == "" || $line == " "* ]]; then
                # ${line%% *} - всё до первого пробела (SteamID)
                # ${line#* } - всё после первого пробела (Имя игрока)
                USERNAMES[${line%% *}]=${line#* }
            fi
        done < "$USERLIST"
        log_message "Загружено ${#USERNAMES[@]} имен игроков из $USERLIST"
    fi
}
# Функция получения читаемого сообщения для игрового события (рейда)
eventmessage(){
    case $1 in
        "army_eikthyr")
            echo "$MSG_EVENT_EIKTHYR"
            ;;
        "army_theelder")
            echo "$MSG_EVENT_THEELDER"
            ;;
        "army_bonemass")
            echo "$MSG_EVENT_BONEMASS"
            ;;
        "army_moder")
            echo "$MSG_EVENT_MODER"
            ;;
        "army_goblin")
            echo "$MSG_EVENT_GOBLIN"
            ;;
        "foresttrolls")
            echo "$MSG_EVENT_FOREST_TROLLS"
            ;;
        "blobs")
            echo "$MSG_EVENT_BLOBS"
            ;;
        "skeletons")
            echo "$MSG_EVENT_SKELETONS"
            ;;
        "surtlings")
            echo "$MSG_EVENT_SURTLINGS"
            ;;
        "army_charredspawner")
            echo "$MSG_EVENT_CHARRED_SPAWNER"
            ;;
        "army_charred")
            echo "$MSG_EVENT_CHARRED"
            ;;
        "wolves")
            echo "$MSG_EVENT_WOLVES"
            ;;
        "bats")
            echo "$MSG_EVENT_BATS"
            ;;
        "ghosts")
            echo "$MSG_EVENT_GHOSTS"
            ;;
        "army_gjall")
            echo "$MSG_EVENT_GJALL"
            ;;
        "hildirboss1")
            echo "$MSG_EVENT_HILDIR_BOSS1"
            ;;
        "hildirboss2")
            echo "$MSG_EVENT_HILDIR_BOSS2"
            ;;
        "hildirboss3")
            echo "$MSG_EVENT_HILDIR_BOSS3"
            ;;
        "army_seekers")
            echo "$MSG_EVENT_SEEKERS"
            ;;
        *)
            echo -e "$MSG_EVENT_UNKNOWN\n$1" # Сообщение для неизвестного события
            ;;
    esac
}
# Функция проверки свободного места на корневом разделе диска
check_disk_space() {
    local threshold=1048576 # Порог: 1GB в килобайтах
    # Получаем количество свободного места в килобайтах для корневого раздела (/)
    local free_space=$(df -k / | awk 'NR==2 {print $4}')
    # Если свободного места меньше порога, отправляем предупреждение
    if [ "$free_space" -lt "$threshold" ]; then
        # Конвертируем килобайты в гигабайты для читаемости
        local free_gb=$(echo "scale=2; $free_space/1024/1024" | bc 2>/dev/null || echo "0")
        log_message "Предупреждение: Заканчивается место! Свободно ${free_gb} GB"
        export free_gb
        send "$MSG_DISK_SPACE_WARNING"
    fi
}
# Функция проверки использования оперативной памяти
check_memory_usage() {
    local threshold=90 # Порог в процентах
    # Вычисляем процент использования памяти: (использовано / всего * 100)
    local memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    # Если использование памяти превышает порог, отправляем предупреждение
    if [ "$memory_usage" -gt "$threshold" ]; then
        log_message "Предупреждение: Высокое потребление памяти! Использовано ${memory_usage}%"
        export memory_usage
        send "$MSG_MEMORY_USAGE_WARNING"
    fi
}
# Инициализация времени последней проверки
last_check_time=$(date +%s)
log_message "Запуск скрипта мониторинга Valheim сервера"
log_message "Мониторим файл: $LOGFILE"
# Загружаем список имен игроков
loadnames
# Объявляем ассоциативный массив для отслеживания АУТЕНТИФИЦИРОВАННЫХ игроков (SteamID -> true)
declare -A AUTHENTICATED_PLAYERS
# Ассоциативный массив для хранения SteamID по имени персонажа
declare -A CHARACTER_TO_STEAMID
# Ассоциативный массив для хранения последнего SteamID для каждого клиента
declare -A LAST_STEAMID_FOR_CLIENT
# Ассоциативный массив для хранения связи SteamID -> CHARACTER_NAME
declare -A STEAMID_TO_CHARACTER
# Основной цикл обработки лога
log_message "Начинаем мониторинг лога..."
tail -Fqn0 "$LOGFILE" | \
while read line ; do
    # Логируем оригинальную строку из лога Valheim
    # log_message "VALHEIM LOG: $line" # Закомментировано для уменьшения лога
    # Обработка различных событий в логе
    if [[ $line == *"Got connection SteamID"* ]]; then
        # Новая попытка подключения - сохраняем SteamID
        STEAMID=$(echo "$line" | grep -oP 'Got connection SteamID \K[0-9]+' | head -1)
        if [[ -n "$STEAMID" ]]; then
            LAST_STEAMID_FOR_CLIENT["$STEAMID"]="$STEAMID"
            log_message "Получен SteamID для подключения: $STEAMID"
            # Если SteamID еще не в кэше имен, пытаемся добавить
            if [[ ! ${USERNAMES[$STEAMID]+abc} ]]; then
                log_message "Найден новый SteamID: $STEAMID"
                addcharname "$STEAMID"
            fi
        fi
    elif [[ $line == *"Got character ZDOID from"* ]]; then
    # Игрок успешно вошел (получил персонажа после ввода пароля)
    CHARACTER_NAME=$(echo "$line" | grep -oP 'Got character ZDOID from \K[^:]+')
    ZDOID=$(echo "$line" | grep -oP 'Got character ZDOID from [^:]+ : \K[0-9:]+')
    # Проверяем, является ли ZDOID "пустым" (0:0) - это означает выход или удаление персонажа
    if [[ "$ZDOID" == "0:0" ]]; then
        log_message "Получен пустой ZDOID для персонажа $CHARACTER_NAME, игнорируем"
        continue
    fi
    # Ищем SteamID для этого персонажа
    STEAMID_FOR_EVENT=""
    # Проверяем, есть ли сохраненный SteamID для этого персонажа
    if [[ -n "${CHARACTER_TO_STEAMID[$CHARACTER_NAME]}" ]]; then
        STEAMID_FOR_EVENT="${CHARACTER_TO_STEAMID[$CHARACTER_NAME]}"
    else
        # Если нет, пытаемся найти последний SteamID
        # Ищем в LAST_STEAMID_FOR_CLIENT
        for sid in "${!LAST_STEAMID_FOR_CLIENT[@]}"; do
            if [[ -n "$sid" ]]; then
                STEAMID_FOR_EVENT="$sid"
                break
            fi
        done
    fi
    if [[ -n "$STEAMID_FOR_EVENT" ]]; then
        # Проверяем, не был ли этот игрок уже аутентифицирован
        if [[ "${AUTHENTICATED_PLAYERS[$STEAMID_FOR_EVENT]}" != "true" ]]; then
            PLAYER_NAME_FOR_EVENT="$(charname "$STEAMID_FOR_EVENT")"
            log_message "Игрок вошел на сервер: $PLAYER_NAME_FOR_EVENT ($STEAMID_FOR_EVENT) с персонажем $CHARACTER_NAME"
            # Сохраняем связь SteamID -> CHARACTER_NAME
            STEAMID_TO_CHARACTER["$STEAMID_FOR_EVENT"]="$CHARACTER_NAME"
            # Помечаем игрока как аутентифицированного
            AUTHENTICATED_PLAYERS["$STEAMID_FOR_EVENT"]="true"
            # Сохраняем связь персонаж-steamid
            CHARACTER_TO_STEAMID["$CHARACTER_NAME"]="$STEAMID_FOR_EVENT"
            # Удаляем из временного хранилища
            unset LAST_STEAMID_FOR_CLIENT["$STEAMID_FOR_EVENT"]
            # Отправляем сообщение только если игрок еще не был аутентифицирован
            export PLAYER_NAME_FOR_EVENT CHARACTER_NAME
            send "$MSG_PLAYER_JOINED"
        else
            log_message "Игрок уже аутентифицирован: $PLAYER_NAME_FOR_EVENT ($STEAMID_FOR_EVENT) с персонажем $CHARACTER_NAME, ZDOID: $ZDOID"
        fi
    else
        # Проверяем, не был ли этот игрок уже аутентифицирован
        player_already_joined=false
        for char in "${!CHARACTER_TO_STEAMID[@]}"; do
            if [[ "$char" == "$CHARACTER_NAME" ]]; then
                player_already_joined=true
                break
            fi
        done
        if [[ "$player_already_joined" != "true" ]]; then
            log_message "Игрок вошел на сервер: Неизвестный игрок с персонажем $CHARACTER_NAME"
            export CHARACTER_NAME
            send "$MSG_UNKNOWN_PLAYER_JOINED"
        else
            log_message "Неизвестный игрок уже вошел на сервер с персонажем $CHARACTER_NAME"
        fi
    fi
    elif [[ $line == *"Closing socket"* ]] || [[ $line == *"Disconnecting socket"* ]]; then
        # Ищем SteamID в строке отключения
        DISCONNECT_STEAMID=$(echo "$line" | grep -oP 'Closing socket \K[0-9]+' | head -1)
        if [[ -z "$DISCONNECT_STEAMID" ]]; then
            DISCONNECT_STEAMID=$(echo "$line" | grep -oP 'Disconnecting socket \K[0-9]+' | head -1)
        fi
        if [[ -n "$DISCONNECT_STEAMID" ]]; then
            # Отправляем уведомление об отключении только если игрок был аутентифицирован
            if [[ "${AUTHENTICATED_PLAYERS[$DISCONNECT_STEAMID]}" == "true" ]]; then
                PLAYER_NAME="$(charname "$DISCONNECT_STEAMID")"
                # Получаем имя персонажа из сохраненной связи
                CHARACTER_NAME_FOR_EVENT="${STEAMID_TO_CHARACTER[$DISCONNECT_STEAMID]:-Unknown}"
                log_message "Игрок отключился: $PLAYER_NAME ($DISCONNECT_STEAMID) с персонажем $CHARACTER_NAME_FOR_EVENT"
                # Экспортируем переменные для использования в сообщении
                export PLAYER_NAME CHARACTER_NAME_FOR_EVENT
                send "$MSG_PLAYER_LEFT"
                # Удаляем игрока из массива отслеживания
                unset AUTHENTICATED_PLAYERS["$DISCONNECT_STEAMID"]
                # Удаляем связь персонаж-steamid
                for char in "${!CHARACTER_TO_STEAMID[@]}"; do
                    if [[ "${CHARACTER_TO_STEAMID[$char]}" == "$DISCONNECT_STEAMID" ]]; then
                        unset CHARACTER_TO_STEAMID["$char"]
                        break
                    fi
                done
                # Удаляем связь steamid-персонаж
                unset STEAMID_TO_CHARACTER["$DISCONNECT_STEAMID"]
            else
                log_message "Отключение неаутентифицированного игрока: $DISCONNECT_STEAMID"
            fi
            # Удаляем из временного хранилища
            unset LAST_STEAMID_FOR_CLIENT["$DISCONNECT_STEAMID"]
        fi
    elif [[ $line == *"Load world"* ]]; then
        WORLDNAME=$(echo "$line" | grep -oP 'Load world \K(.+)')
        log_message "Загружен мир: $WORLDNAME"
        export WORLDNAME VALHEIMVERSION # VALHEIMVERSION может быть установлен позже, но экспортируем заранее
        send "$MSG_SERVER_STARTING"
    elif [[ $line == *"day:"* ]]; then
        DAY=$(echo "$line" | grep -oP 'day:\K(\d+)')
        DAY=$((DAY + 1))
        log_message "Наступил день: $DAY"
        export DAY
        send "$MSG_NEW_DAY"
    elif [[ $line == *"OnApplicationQuit"* ]]; then
        log_message "Сервер выключается"
        send "$MSG_SERVER_SHUTDOWN"
    elif [[ $line == *"Opened Steam server"* ]]; then
        log_message "Сервер запустился"
        export VALHEIMVERSION # VALHEIMVERSION может быть установлен позже, но экспортируем заранее
        send "$MSG_SERVER_STARTING"
    elif [[ $line == *"Random event"* ]]; then
        EVENT=$(echo "$line" | grep -oP 'Random event set:\K([0-9a-zA-Z_]+)')
        EVENTMSG="$(eventmessage ${EVENT})" # Получаем сообщение
        log_message "Начался рейд: $EVENT"
        export EVENTMSG
        send "$MSG_RAID_STARTED"
    elif [[ $line == *"Valheim version"* ]]; then
        VALHEIMVERSION=$(echo "$line" | grep -oP 'Valheim version:\K(.+)')
        log_message "Версия Valheim: $VALHEIMVERSION"
    elif [[ $line == *"Network version check"* ]]; then
        CLIENT_VERSION=$(echo "$line" | grep -oP 'their:(\d+)' | cut -d':' -f2)
        SERVER_VERSION=$(echo "$line" | grep -oP 'mine:(\d+)' | cut -d':' -f2)
        log_message "Проверка версии: клиент=$CLIENT_VERSION, сервер=$SERVER_VERSION"
        # Пробуем прочитать следующую строку (таймаут 5 секунд)
        if read -t 5 NEXT_LINE; then
            if [[ $NEXT_LINE == *"incompatible version"* ]]; then
                if [[ $CLIENT_VERSION -gt $SERVER_VERSION ]]; then
                    # Получаем SteamID из предыдущей строки
                    VERSION_CHECK_STEAMID=$(echo "$line" | grep -oP '76[0-9]{15}' | head -1)
                    if [[ -n "$VERSION_CHECK_STEAMID" ]]; then
                        PLAYER_NAME="$(charname "$VERSION_CHECK_STEAMID")"
                        log_message "Обнаружена несовместимость версий! Требуется обновление сервера."
                        export PLAYER_NAME CLIENT_VERSION SERVER_VERSION
                        send "$MSG_VERSION_MISMATCH"
                    fi
                fi
            fi
        fi
    fi
    # Вызов проверок ресурсов хоста
    current_time=$(date +%s)
    if (( current_time - last_check_time >= CHECK_INTERVAL )); then
        log_message "Выполняем проверку ресурсов системы..."
        check_disk_space
        check_memory_usage
        last_check_time=$current_time
    fi
done
