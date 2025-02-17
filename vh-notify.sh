#!/bin/bash

### Valheim Notify — это простой BASH-скрипт, который отправляет уведомления сервера Valheim в чат Telegram. Он нацелен на простоту использования и должен работать на большинстве разновидностей Linux.
### Скрипт знает только о 8 событиях, которые можно проанализировать из журнала консоли сервера:
### 1. Игрок присоединился.
### 2. Игрок отключился.
### 3. Игрок заспавнился.
### 4. Игрок умер.
### 5. Все игроки в сети легли спать, чтобы пропустить ночь, и начался новый день.
### 6. Запускается случайное событие, см. https://valheim.fandom.com/wiki/Events
### 7. Запуск сервера и загрузка мира.
### 8. Выключение сервера.
###
### Вам нужно настроить CHATID, THREAD_ID, KEY и LOGFILE
###
### Скрипт будет искать 64-битные Steam ID, которые подключаются к серверу
### Соответствующее имя Steam хранится в usernames.txt
### Вы также можете вручную добавлять Steam ID и (изменять) имена, скрипт не будет перезаписать
### Для смерти персонажа и (возрождения) имя персонажа Valheim анализируется из сообщения журнала
###
### Запустите этот скрипт в фоновом режиме и/или добавьте его в cron (crontab -e), затем
### @reboot /home/vhserver/valheim-notify/vh-notify.sh &

### Не забудьте добавить в скрипт запуска сервера в строку ./valheim_server.x86_64 ключ: -logfile "/Valheim-server/valheim_log.txt", где "/Valheim-server/valheim_log.txt" - путь к файлу лога.

### Переменные:
### CHATID="-0000000000000" - Укажите ID чата
### THREAD_ID="1234" - Укажите ID потока, если необходимо отправлять в конкретную тему. Если это обычный чат, можно не указывать.
### KEY="1231231231:XXxxXXxxXXxxXXxx" - ID бота
### LOGFILE="./Valheim/logs/valheim_log.txt" - Путь к файлу лога

CHATID="" # Укажите ID чата
THREAD_ID=""  # Укажите ID потока, если необходимо отправлять в конкретную тему. Можно не указывать.
KEY="" # ID бота
LOGFILE="/Valheim-server/valheim_log.txt" # путь к файлу лога

USERLIST="/Valheim-server/usernames.txt"
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
            send "${CHARNAME} подключился к серверу"

        elif [[ $CLINE == *"Closing"* ]]; then
            send "$CHARNAME отключился от сервера"

        elif [[ $line == *"Load world"* ]]; then
            WORLDNAME=$(echo "$line" | grep -oP 'Load world \K(.+)')
	    send "Сервер запустился (version $VALHEIMVERSION) и загрузил мир $WORLDNAME"

        elif [[ $line == *"day:"* ]]; then
            DAY=$(echo "$line" | grep -oP 'day:\K(\d+)')
	    DAY=$(($DAY + 1))
            send "Все игроки легли спать. Наступил день $DAY"

        elif [[ $line == *"OnApplicationQuit"* ]]; then
            send "Сервер выключился."

        elif [[ $CLINE == *"Random event"* ]]; then
            EVENT=$(echo "$line" | grep -oP 'Random event set:\K([0-9a-zA-Z_]+)')
            EVENTMSG="$(eventmessage ${EVENT})"
            send $'Random event triggered!\n'"$EVENTMSG"

        elif [[ $CLINE == *"Valheim version"* ]]; then
            VALHEIMVERSION=$(echo "$line" | grep -oP 'Valheim version:\K(.+)')
        
        else
            # Only ZOID options left, if ends with in 0:0 then player died, otherwise spawned
            CHARNAME=$(echo "$CLINE" | grep -oP 'ZDOID from \K(.+)(?= :)')

            # line ending match on 0:0 does not seem to work, this does
            if [[ $line == *": 0:"* ]]; then
                send "$CHARNAME погиб."

            else
                send "$CHARNAME заспавнился."

            fi

        fi
    fi
done
