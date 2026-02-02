#!/bin/bash

BASE_URL="https://prod-api.trackprep.in/practice"
SUBJECTS=("Biology" "Chemistry" "Physics")

for SUB in "${SUBJECTS[@]}"; do
    echo "Processing Subject: $SUB"
    
    # Get Chapter List
    CHAPTERS=$(curl -s "$BASE_URL/chapters/${SUB,,}")
    
    echo "$CHAPTERS" | jq -c '.[]' | while read -r chap; do
        CHAP_NAME=$(echo "$chap" | jq -r '.name')
        CHAP_SLUG=$(echo "$CHAP_NAME" | jq -sRr @uri)
        
        # Get Topic List for this chapter
        TOPICS=$(curl -s "$BASE_URL/topics/${SUB,,}/$CHAP_SLUG")
        
        echo "$TOPICS" | jq -c '.[]' | while read -r top; do
            TOP_NAME=$(echo "$top" | jq -r '.name')
            TOTAL_QS=$(echo "$top" | jq -r '.questionCount')
            
            # Sanitizing folder and file names
            DIR="data/$SUB/${CHAP_NAME// /_}"
            FILE="$DIR/${TOP_NAME// /_}.json"
            mkdir -p "$DIR"

            # Initialize file if not exists
            if [ ! -f "$FILE" ]; then echo "[]" > "$FILE"; fi

            # Check existing count
            CURRENT_COUNT=$(jq 'length' "$FILE")

            if [ "$CURRENT_COUNT" -lt "$TOTAL_QS" ]; then
                echo "Downloading: $SUB -> $CHAP_NAME -> $TOP_NAME ($CURRENT_COUNT/$TOTAL_QS)"
                
                # Calculate which page to start from
                START_PAGE=$(( (CURRENT_COUNT / 20) + 1 ))
                MAX_PAGE=$(( (TOTAL_QS + 19) / 20 ))

                for (( p=$START_PAGE; p<=$MAX_PAGE; p++ )); do
                    # Random Sleep to mimic human behavior
                    SLEEP_TIME=$((15 + RANDOM % 15))
                    echo "   Page $p: Waiting ${SLEEP_TIME}s..."
                    sleep $SLEEP_TIME

                    RESP=$(curl -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
                               -s "$BASE_URL/questions?subject=$SUB&chapter=$CHAP_SLUG&topic=$(echo "$TOP_NAME" | jq -sRr @uri)&page=$p&limit=20&sortBy=latest")

                    # Check for Rate Limit / Block
                    if echo "$RESP" | grep -q "Access Denied"; then
                        echo "!!! BLOCKED !!! IP Banned. Saving progress and exiting."
                        exit 1
                    fi

                    # Append new questions and remove duplicates based on ID
                    NEW_QS=$(echo "$RESP" | jq '.questions')
                    COMBINED=$(jq -s '.[0] + .[1] | unique_by(.id)' "$FILE" <(echo "$NEW_QS"))
                    echo "$COMBINED" > "$FILE"
                    
                    # Stop after 3 pages per topic per run to stay under GitHub's time limit
                    # This ensures the bot eventually finishes everything without a 24hr ban
                    if [ $p -ge $((START_PAGE + 2)) ]; then break 2; fi
                done
            fi
        done
    done
done
