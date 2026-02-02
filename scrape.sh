#!/bin/bash
SUB=$1
BASE_URL="https://prod-api.trackprep.in/practice"

# Lowercase subject for the API path
SUB_LOWER=$(echo "$SUB" | tr '[:upper:]' '[:lower:]')

echo "Focusing on: $SUB (Slug: $SUB_LOWER)"

# Function to fetch with retry
fetch_api() {
    local url=$1
    local retry=0
    local max_retries=3
    while [ $retry -lt $max_retries ]; do
        response=$(curl -s -f "$url")
        if [ $? -eq 0 ] && [ ! -z "$response" ]; then
            echo "$response"
            return 0
        fi
        echo "Retry $((retry+1)) for $url..." >&2
        sleep 5
        retry=$((retry+1))
    done
    return 1
}

# Fetch Chapter List
RAW_CHAPTERS=$(fetch_api "$BASE_URL/chapters/$SUB_LOWER")

if [ -z "$RAW_CHAPTERS" ] || [[ $(echo "$RAW_CHAPTERS" | jq 'type') != "array" ]]; then
    echo "Error: Could not get valid chapters for $SUB. Check API/Network."
    exit 1
fi

echo "$RAW_CHAPTERS" | jq -c '.[]' | while read -r chap; do
    CHAP_NAME=$(echo "$chap" | jq -r '.name // empty')
    [ -z "$CHAP_NAME" ] && continue
    
    CHAP_SLUG=$(echo "$CHAP_NAME" | jq -sRr @uri)
    
    # Get Topic List
    RAW_TOPICS=$(fetch_api "$BASE_URL/topics/$SUB_LOWER/$CHAP_SLUG")
    if [ -z "$RAW_TOPICS" ] || [[ $(echo "$RAW_TOPICS" | jq 'type') != "array" ]]; then continue; fi

    echo "$RAW_TOPICS" | jq -c '.[]' | while read -r top; do
        TOP_NAME=$(echo "$top" | jq -r '.name // empty')
        TOTAL_QS=$(echo "$top" | jq -r '.questionCount // 0')
        [ -z "$TOP_NAME" ] || [ "$TOTAL_QS" -eq 0 ] && continue

        # Save Path: Subject/Chapter/Topic.json
        DIR="data/$SUB/${CHAP_NAME// /_}"
        FILE="$DIR/${TOP_NAME// /_}.json"
        mkdir -p "$DIR"
        [ ! -f "$FILE" ] && echo "[]" > "$FILE"

        CURRENT_COUNT=$(jq 'length' "$FILE")
        
        if [ "$CURRENT_COUNT" -lt "$TOTAL_QS" ]; then
            echo "Syncing: $TOP_NAME ($CURRENT_COUNT/$TOTAL_QS)"
            START_PAGE=$(( (CURRENT_COUNT / 20) + 1 ))
            
            # Fetch 5 pages per run
            for (( p=$START_PAGE; p<=$((START_PAGE + 5)); p++ )); do
                [ $p -gt $(( (TOTAL_QS + 19) / 20 )) ] && break
                
                sleep $((10 + RANDOM % 10))
                
                # Note: Subject name in query param might need TitleCase ($SUB)
                URL="$BASE_URL/questions?subject=$SUB&chapter=$CHAP_SLUG&topic=$(echo "$TOP_NAME" | jq -sRr @uri)&page=$p&limit=20"
                RESP=$(curl -s "$URL")
                
                if echo "$RESP" | grep -q "Access Denied"; then
                    echo "Blocked on $URL. Stopping run."
                    exit 1
                fi
                
                NEW_QS=$(echo "$RESP" | jq '.questions // []')
                if [ "$NEW_QS" != "[]" ]; then
                    jq -s '.[0] + .[1] | unique_by(.id)' "$FILE" <(echo "$NEW_QS") > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"
                fi
            done
        fi
    done
done
