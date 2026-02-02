#!/bin/bash
SUB=$1 # Takes Biology, Chemistry, or Physics from matrix
BASE_URL="https://prod-api.trackprep.in/practice"

echo "Focusing on: $SUB"
CHAPTERS=$(curl -s "$BASE_URL/chapters/${SUB,,}")

echo "$CHAPTERS" | jq -c '.[]' | while read -r chap; do
    CHAP_NAME=$(echo "$chap" | jq -r '.name')
    CHAP_SLUG=$(echo "$CHAP_NAME" | jq -sRr @uri)
    TOPICS=$(curl -s "$BASE_URL/topics/${SUB,,}/$CHAP_SLUG")
    
    echo "$TOPICS" | jq -c '.[]' | while read -r top; do
        TOP_NAME=$(echo "$top" | jq -r '.name')
        TOTAL_QS=$(echo "$top" | jq -r '.questionCount')
        DIR="data/$SUB/${CHAP_NAME// /_}"
        FILE="$DIR/${TOP_NAME// /_}.json"
        mkdir -p "$DIR"
        [ ! -f "$FILE" ] && echo "[]" > "$FILE"

        CURRENT_COUNT=$(jq 'length' "$FILE")
        if [ "$CURRENT_COUNT" -lt "$TOTAL_QS" ]; then
            START_PAGE=$(( (CURRENT_COUNT / 20) + 1 ))
            # Increase limit to 10 pages per run (200 questions)
            for (( p=$START_PAGE; p<=$((START_PAGE + 10)); p++ )); do
                [ $p -gt $(( (TOTAL_QS + 19) / 20 )) ] && break
                
                sleep $((5 + RANDOM % 5)) # Shorter sleep but still safe
                RESP=$(curl -s "$BASE_URL/questions?subject=$SUB&chapter=$CHAP_SLUG&topic=$(echo "$TOP_NAME" | jq -sRr @uri)&page=$p&limit=20")
                
                if echo "$RESP" | grep -q "Access Denied"; then exit 1; fi
                
                NEW_QS=$(echo "$RESP" | jq '.questions')
                COMBINED=$(jq -s '.[0] + .[1] | unique_by(.id)' "$FILE" <(echo "$NEW_QS"))
                echo "$COMBINED" > "$FILE"
            done
        fi
    done
done
