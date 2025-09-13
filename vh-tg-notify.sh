#!/bin/bash

KEY="0000000000:XXXXXXXxxxxxxxXXXXXXXXXxxxxxx"
CHATID="-1234567890"
THREAD_ID=""
LOGFILE="/root/Valheim/logs/valheim_log.txt"
USERLIST="/root/Valheim/usernames.txt"

TIMEOUT="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
STEAMURL="https://steamcommunity.com/profiles/"
VALHEIMVERSION="Not set"

# Функция отправки сообщения в Telegram
send(){
    local url="$URL"
    local data="chat_id=$CHATID&disable_web_page_preview=1&text=$1"

    if [ -n "$THREAD_ID" ]; then
        data="$data&message_thread_id=$THREAD_ID"
    fi

    curl -s --max-time $TIMEOUT -d "$data" "$url" > /dev/null
}

# Функция добавления имени игрока по его SteamID в файл USERLIST
addcharname(){
    # attempt to add a player name using their steam id
    NAME=$(curl -sL --max-time $TIMEOUT $STEAMURL$1 | grep -oPm1 'actual_persona_name">\K(.+)(?=</span>)')
    if [[ $NAME ]]; then
        echo "$1 $NAME" >> $USERLIST
        loadnames
    fi
}

# Функция получения имени игрока по SteamID из ассоциативного массива
charname(){
    if [ ${USERNAMES[$1]+abc} ]; then
        echo ${USERNAMES[$1]}
    else
        echo "Unknown ($1)"
    fi
}

# Функция загрузки SteamID и имен игроков из файла в ассоциативный массив USERNAMES
loadnames(){
    declare -gA USERNAMES
    if ! [[ -r $USERLIST ]]; then
        echo "Warning: cannot find or read $USERLIST"
    else
        while IFS= read -r line; do
            if ! [[ $line == "#"* || $line == "" || $line == " "* ]]; then
                USERNAMES[${line%% *}]=${line#* }
            fi
        done < "$USERLIST"
    fi
}

# Функция получения читаемого сообщения для игрового события (рейда)
eventmessage(){
    case $1 in
    
        "army_eikthyr")
            echo $'Эйктюр объединяет существ леса.'
            ;;
            
        "army_theelder")
            echo $'Лес движется...'
            ;;
            
        "army_bonemass")
            echo $'Вонь с болот.'
            ;;
        
        "army_moder")
            echo $'Холодный ветер дует с гор.'
            ;;
        
        "army_goblin")
            echo $'Орда атакует'
            ;;
        
        "foresttrolls")
            echo $'Земля трясется.'
            ;;
        
        "blobs")
            echo $'Вонь с болот.'
            ;;
        
        "skeletons")
            echo $'Незваные кости.'
            ;;
            
        "surtlings")
            echo $'В воздухе висит запах серы...'
            ;;
        
        "army_charredspawner")
            echo $'Восстание мертвецов.'
            ;;
        
        "army_charred")
            echo $'Марш армии мертвых.'
            ;;
        
        "wolves")
            echo $'На вас охотятся...'
            ;;
        
        "bats")
            echo $'Вы размешали котел.'
            ;;
        
        "ghosts")
            echo $'Мороз по коже пробежал...'
            ;;
        
        "army_gjall")
            echo $'Дарова, Гьялль!?'
            ;;
        
        "hildirboss1")
            echo $'Она вот-вот задаст Вам жару.'
            ;;
        
        "hildirboss2")
            echo $'По Вам пробежал холодок.'
            ;;
        
        "hildirboss3")
            echo $'Они были братанами, парень...'
            ;;
        
        "army_seekers")
            echo $'Они ищут вас.'
            ;;
        
        *)
            echo -e "Unknown event!\n$1"
            ;;

    esac
}

# Проверка свободного места на диске
check_disk_space() {
    local threshold=1048576									# 1GB в килобайтах
	local free_space=$(df -k / | awk 'NR==2 {print $4}')	# Получаем количество свободного места в килобайтах для корневого раздела (/)
    
    # Если свободного места меньше порога, отправляем предупреждение
	if [ "$free_space" -lt "$threshold" ]; then
        # Конвертируем килобайты в гигабайты для читаемости
		local free_gb=$(echo "scale=2; $free_space/1024/1024" | bc)
        send "⚠️ ВНИМАНИЕ: Мало места на диске! Свободно только ${free_gb} GB"
    fi
}

# Проверка использования памяти
check_memory_usage() {
    local threshold=90													# Порог в процентах
    local memory_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}') # Вычисляем процент использования памяти: (использовано / всего * 100)
    memory_usage=${memory_usage%.*}
    
    # Если использование памяти превышает порог, отправляем предупреждение
	if [ "$memory_usage" -gt "$threshold" ]; then
        send "⚠️ ВНИМАНИЕ: Высокое использование памяти! Использовано ${memory_usage}%"
    fi
}

CHECK_INTERVAL=300 		#переменная интервала проверки занятой памяти и места на диске

# Загружаем список имен игроков в ассоциативный массив при старте скрипта
loadnames

# Объявляем ассоциативный массив для отслеживания аутентифицированных игроков
declare -gA AUTHENTICATED_PLAYERS

# Основной цикл: читаем лог сервера в реальном времени (tail -F)
# и фильтруем строки через grep, оставляя только значимые для нас события
tail -Fqn0 $LOGFILE | \
while read line ; do
    echo "$line" | grep -Eq "ZDOID|handshake|Closing|day:|Load world|OnApplicationQuit|Random event|Valheim version"
    if [ $? = 0 ]; then

        # Сохраняем текущую строку лога, т.к. она может быть изменена при обработке
        CLINE=$line
        STEAMID=$(echo "$CLINE" | grep -oP '76[0-9]{10,}')
        if [[ $STEAMID ]] &&  [ ! ${USERNAMES[$STEAMID]+abc} ]; then
            addcharname $STEAMID
            CHARNAME="$(charname ${STEAMID})"

        elif [[ $STEAMID ]]; then
            CHARNAME="$(charname ${STEAMID})"

        fi

        if [[ $CLINE == *"handshake"* ]]; then
            # Инициализируем запись об игроке, но не помечаем как аутентифицированного
            if [[ $STEAMID ]]; then
                AUTHENTICATED_PLAYERS[$STEAMID]=false
            fi
            : # Пустая команда

        elif [[ $CLINE == *"Server: New peer connected"* ]]; then
            send "${CHARNAME} подключился к серверу."
            # Помечаем игрока как успешно аутентифицированного
            if [[ $STEAMID ]]; then
                AUTHENTICATED_PLAYERS[$STEAMID]=true
            fi

        elif [[ $CLINE == *"Peer "*" has wrong password"* ]]; then
            # Помечаем игрока как НЕаутентифицированного при неверном пароле
            if [[ $STEAMID ]]; then
                AUTHENTICATED_PLAYERS[$STEAMID]=false
            fi

        elif [[ $CLINE == *"Closing"* ]] || [[ $CLINE == *"Disconnecting socket"* ]]; then
            # Отправляем уведомление об отключении только если игрок был аутентифицирован
            if [[ $STEAMID ]] && [[ ${AUTHENTICATED_PLAYERS[$STEAMID]} == true ]]; then
                send "$CHARNAME отключился от сервера."
            fi
            # Удаляем игрока из массива отслеживания при любом исходе
            if [[ $STEAMID ]]; then
                unset AUTHENTICATED_PLAYERS[$STEAMID]
            fi

        elif [[ $line == *"Load world"* ]]; then
            WORLDNAME=$(echo "$line" | grep -oP 'Load world \K(.+)')
	    send "✅ Сервер запускается (версия $VALHEIMVERSION). Мир $WORLDNAME загружен."

        elif [[ $line == *"day:"* ]]; then
            DAY=$(echo "$line" | grep -oP 'day:\K(\d+)')
	    DAY=$(($DAY + 1))
            send "Все игроки легли спать. Наступил день $DAY"

        elif [[ $line == *"OnApplicationQuit"* ]]; then
            send "⏹ Сервер выключается."

        elif [[ $CLINE == *"Random event"* ]]; then
            EVENT=$(echo "$line" | grep -oP 'Random event set:\K([0-9a-zA-Z_]+)')
            EVENTMSG="$(eventmessage ${EVENT})"
            send $'Начался рейд!\n'"$EVENTMSG"

        elif [[ $CLINE == *"Valheim version"* ]]; then
            VALHEIMVERSION=$(echo "$line" | grep -oP 'Valheim version:\K(.+)')
	    
	# Проверка конфликта версий
        elif [[ $CLINE == *"Network version check"* ]]; then
            # Сохраняем версии клиента и сервера
            SERVER_VERSION=$(echo "$CLINE" | grep -oP 'mine:(\d+)' | cut -d':' -f2)
            CLIENT_VERSION=$(echo "$CLINE" | grep -oP 'their:(\d+)' | cut -d':' -f2)

            # Ждем строку "incompatible version" для подтверждения несовместимости
            read -t 5 NEXT_LINE
            if [[ $NEXT_LINE == *"incompatible version"* ]]; then
                # Подтверждаем, что сервер старее клиента
                if [[ $CLIENT_VERSION -gt $SERVER_VERSION ]]; then
                    ## отправка уведомления об устаревшем сервере
                    send "⚠️ Игрок ${CHARNAME} подключился с версией ${CLIENT_VERSION}, версия сервера ${SERVER_VERSION}. Необходимо обновление сервера!"
                fi
            fi

        else
            # Only ZOID options left, if ends with in 0:0 then player died, otherwise spawned
            CHARNAME=$(echo "$CLINE" | grep -oP 'ZDOID from \K(.+)(?= :)')

            # line ending match on 0:0 does not seem to work, this does
            if [[ $line == *": 0:"* ]]; then
                send "$CHARNAME погиб."

            else
                send "$CHARNAME Появился."

            fi

        fi
    fi
    
    #Вызов проверок ресурсов хоста
    current_time=$(date +%s)
    if (( current_time - last_check_time >= CHECK_INTERVAL )); then
        check_disk_space
        check_memory_usage
        last_check_time=$current_time
    fi
done
