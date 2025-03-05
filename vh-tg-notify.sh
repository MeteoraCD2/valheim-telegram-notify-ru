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

send(){
    local url="$URL"
    local data="chat_id=$CHATID&disable_web_page_preview=1&text=$1"

    if [ -n "$THREAD_ID" ]; then
        data="$data&message_thread_id=$THREAD_ID"
    fi

    curl -s --max-time $TIMEOUT -d "$data" "$url" > /dev/null
}

addcharname(){
    # attempt to add a player name using their steam id
    NAME=$(curl -sL --max-time $TIMEOUT $STEAMURL$1 | grep -oPm1 'actual_persona_name">\K(.+)(?=</span>)')
    if [[ $NAME ]]; then
        echo "$1 $NAME" >> $USERLIST
        loadnames
    fi
}

charname(){
    if [ ${USERNAMES[$1]+abc} ]; then
        echo ${USERNAMES[$1]}
    else
        echo "Unknown ($1)"
    fi
}

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
    local threshold=1048576 # 1GB в килобайтах
    local free_space=$(df -k / | awk 'NR==2 {print $4}')
    
    if [ "$free_space" -lt "$threshold" ]; then
        local free_gb=$(echo "scale=2; $free_space/1024/1024" | bc)
        send "⚠️ ВНИМАНИЕ: Мало места на диске! Свободно только ${free_gb} GB"
    fi
}

# Проверка использования памяти
check_memory_usage() {
    local threshold=90 # процентов
    local memory_usage=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    memory_usage=${memory_usage%.*}
    
    if [ "$memory_usage" -gt "$threshold" ]; then
        send "⚠️ ВНИМАНИЕ: Высокое использование памяти! Использовано ${memory_usage}%"
    fi
}

CHECK_INTERVAL=300 #переменная интервала проверки занятой памяти и места на диске

loadnames

tail -Fqn0 $LOGFILE | \
while read line ; do
    echo "$line" | grep -Eq "ZDOID|handshake|Closing|day:|Load world|OnApplicationQuit|Random event|Valheim version"
    if [ $? = 0 ]; then

        # store $line in dedicated var as it will unexplainably get reset when a steam id is added
        CLINE=$line
        STEAMID=$(echo "$CLINE" | grep -oP '76[0-9]{10,}')
        if [[ $STEAMID ]] &&  [ ! ${USERNAMES[$STEAMID]+abc} ]; then
            addcharname $STEAMID
            CHARNAME="$(charname ${STEAMID})"

        elif [[ $STEAMID ]]; then
            CHARNAME="$(charname ${STEAMID})"

        fi

        if [[ $CLINE == *"handshake"* ]]; then
            send "${CHARNAME} подключился к серверу."

        elif [[ $CLINE == *"Closing"* ]]; then
            send "$CHARNAME отключился от сервера."

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
    
    #Проверка ресурсов хоста
    current_time=$(date +%s)
    if (( current_time - last_check_time >= CHECK_INTERVAL )); then
        check_disk_space
        check_memory_usage
        last_check_time=$current_time
    fi
done
