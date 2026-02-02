#!/bin/bash
SUB=$1
BASE_URL="https://prod-api.trackprep.in/practice"

echo "Focusing on: $SUB"
CHAPTERS_JSON=$(curl -s "$BASE_URL/chapters/${SUB,,}")

# Check if response is valid JSON array
if ! echo "$CHAPTERS_JSON" | jq -e '. | isarray' >/dev/null 2>&1; then
    echo "Error: Invalid response from chapters API. Probably blocked or down."
    exit 1
fi

echo "$CHAPTERS_JSON" | jq -c '.[]' | while read -r chap; do
    CHAP_NAME=$(echo "$chap" | jq -r '.name // empty')
    [ -z "$CHAP_NAME" ] && continue
    
    CHAP_SLUG=$(echo "$CHAP_NAME" | jq -sRr @uri)
    TOPICS_JSON=$(curl -s "$BASE_URL/topics/${SUB,,}/$CHAP_SLUG")
    
    # Validate Topics JSON
    if ! echo "$TOPICS_JSON" | jq -e '. | isarray' >/dev/null 2>&1; then continue; fi

    echo "$TOPICS_JSON" | jq -c '.[]' | while read -r top; do
        TOP_NAME=$(echo "$top" | jq -r '.name // empty')
        TOTAL_QS=$(echo "$top" | jq -r '.questionCount // 0')
        [ -z "$TOP_NAME" ] || [ "$TOTAL_QS" -eq 0 ] && continue

        DIR="data/$SUB/${CHAP_NAME// /_}"
        FILE="$DIR/${TOP_NAME// /_}.json"
        mkdir -p "$DIR"
        [ ! -f "$FILE" ] && echo "[]" > "$FILE"

        CURRENT_COUNT=$(jq 'length' "$FILE")
        if [ "$CURRENT_COUNT" -lt "$TOTAL_QS" ]; then
            START_PAGE=$(( (CURRENT_COUNT / 20) + 1 ))
            for (( p=$START_PAGE; p<=$((START_PAGE + 5)); p++ )); do
                [ $p -gt $(( (TOTAL_QS + 19) / 20 )) ] && break
                
                sleep $((10 + RANDOM % 10))
                RESP=$(curl -s "$BASE_URL/questions?subject=$SUB&chapter=$CHAP_SLUG&topic=$(echo "$TOP_NAME" | jq -sRr @uri)&page=$p&limit=20")
                
                # Critical: Check if it's actual question data or an error
                if ! echo "$RESP" | jq -e '.questions' >/dev/null 2>&1; then
                    echo "Access Denied or API Error on page $p. Stopping."
                    exit 1
                fi
                
                NEW_QS=$(echo "$RESP" | jq '.questions')
                COMBINED=$(jq -s '.[0] + .[1] | unique_by(.id)' "$FILE" <(echo "$NEW_QS"))
                echo "$COMBINED" > "$FILE"
            done
        fi
    done
done
