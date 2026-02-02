#!/bin/bash
SUB=$1
BASE_URL="https://prod-api.trackprep.in/practice"

echo "Focusing on: $SUB"

# Fetch Chapter List and validate JSON
RAW_CHAPTERS=$(curl -s "$BASE_URL/chapters/${SUB,,}")
if [[ $(echo "$RAW_CHAPTERS" | jq 'type') != "array" ]]; then
    echo "Error: Invalid API response for chapters. Check Subject name."
    exit 1
fi

echo "$RAW_CHAPTERS" | jq -c '.[]' | while read -r chap; do
    CHAP_NAME=$(echo "$chap" | jq -r '.name // empty')
    [ -z "$CHAP_NAME" ] && continue
    
    CHAP_SLUG=$(echo "$CHAP_NAME" | jq -sRr @uri)
    
    # Get Topic List
    RAW_TOPICS=$(curl -s "$BASE_URL/topics/${SUB,,}/$CHAP_SLUG")
    if [[ $(echo "$RAW_TOPICS" | jq 'type') != "array" ]]; then continue; fi

    echo "$RAW_TOPICS" | jq -c '.[]' | while read -r top; do
        TOP_NAME=$(echo "$top" | jq -r '.name // empty')
        TOTAL_QS=$(echo "$top" | jq -r '.questionCount // 0')
        [ -z "$TOP_NAME" ] || [ "$TOTAL_QS" -eq 0 ] && continue

        # Save Path
        DIR="data/$SUB/${CHAP_NAME// /_}"
        FILE="$DIR/${TOP_NAME// /_}.json"
        mkdir -p "$DIR"
        [ ! -f "$FILE" ] && echo "[]" > "$FILE"

        CURRENT_COUNT=$(jq 'length' "$FILE")
        
        if [ "$CURRENT_COUNT" -lt "$TOTAL_QS" ]; then
            echo "Syncing $TOP_NAME: $CURRENT_COUNT/$TOTAL_QS"
            START_PAGE=$(( (CURRENT_COUNT / 20) + 1 ))
            
            # Limit to 5 pages per run to keep it fast and safe
            for (( p=$START_PAGE; p<=$((START_PAGE + 5)); p++ )); do
                [ $p -gt $(( (TOTAL_QS + 19) / 20 )) ] && break
                
                sleep $((5 + RANDOM % 10))
                RESP=$(curl -s "$BASE_URL/questions?subject=$SUB&chapter=$CHAP_SLUG&topic=$(echo "$TOP_NAME" | jq -sRr @uri)&page=$p&limit=20")
                
                if echo "$RESP" | grep -q "Access Denied"; then
                    echo "IP Blocked. Exiting."
                    exit 1
                fi
                
                NEW_QS=$(echo "$RESP" | jq '.questions // []')
                if [[ "$NEW_QS" != "[]" ]]; then
                    # Atomic merge to prevent corruption
                    jq -s '.[0] + .[1] | unique_by(.id)' "$FILE" <(echo "$NEW_QS") > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"
                fi
            done
        fi
    done
done
