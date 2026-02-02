import requests
import json
import os
import time
import math
from urllib.parse import quote, quote_plus

BASE_URL = "https://prod-api.trackprep.in/practice"
DATA_DIR = "data"
SLEEP_TIME = 4          # increased to reduce 429 chance
RETRY_SLEEP = 90        # longer wait on rate limit
MAX_RETRIES = 3

def make_request(url, retries=0):
    try:
        time.sleep(SLEEP_TIME)
        response = requests.get(url, timeout=15)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as e:
        if response.status_code == 429 and retries < MAX_RETRIES:
            print(f"Rate limited (429). Waiting {RETRY_SLEEP}s... (attempt {retries+1})")
            time.sleep(RETRY_SLEEP)
            return make_request(url, retries + 1)
        print(f"HTTP Error {response.status_code} on {url}: {response.text[:300]}")
        raise
    except Exception as e:
        print(f"Request failed for {url}: {str(e)}")
        raise

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def clean_name(name):
    return name.lower().replace(" ", "_").replace(",", "").replace("(", "").replace(")", "").replace("&", "and")

def save_questions(subject, chapter, topic, questions):
    subject_dir = os.path.join(DATA_DIR, clean_name(subject))
    ensure_dir(subject_dir)
    chapter_dir = os.path.join(subject_dir, clean_name(chapter))
    ensure_dir(chapter_dir)
    topic_file = clean_name(topic) + ".json"
    file_path = os.path.join(chapter_dir, topic_file)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump({"questions": questions}, f, indent=2, ensure_ascii=False)
    print(f"Saved {len(questions)} questions → {file_path}")

def fetch_all_questions(subject, chapter, topic, qcount):
    all_questions = []
    limit = 20
    page = 1
    while True:
        encoded_chapter = quote_plus(chapter)
        encoded_topic   = quote_plus(topic)
        url = f"{BASE_URL}/questions?subject={subject}&chapter={encoded_chapter}&topic={encoded_topic}&page={page}&limit={limit}&sortBy=latest"
        print(f"Fetching page {page} → {url}")
        
        data = make_request(url)
        questions = data.get("questions", [])
        all_questions.extend(questions)
        
        if len(questions) < limit:
            break  # no more pages
        page += 1
        if len(all_questions) >= qcount:
            break
    
    return all_questions

def main():
    ensure_dir(DATA_DIR)
    
    filters = make_request(f"{BASE_URL}/filters")
    subjects = filters.get("subjects", [])
    print(f"Found subjects: {subjects}")
    
    for subject in subjects:
        chapters = make_request(f"{BASE_URL}/chapters/{subject.lower()}")
        print(f"  → {len(chapters)} chapters in {subject}")
        
        for chap in chapters:
            chapter_name = chap["name"]
            topics_url = f"{BASE_URL}/topics/{subject.lower()}/{quote(chapter_name.lower())}"
            topics = make_request(topics_url)
            print(f"    → {len(topics)} topics in {chapter_name}")
            
            for top in topics:
                topic_name = top["name"]
                qcount = top.get("qcount", 0)
                print(f"      → {topic_name} ({qcount} questions)")
                
                if qcount == 0:
                    continue
                    
                questions = fetch_all_questions(subject, chapter_name, topic_name, qcount)
                save_questions(subject, chapter_name, topic_name, questions)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("SCRIPT FAILED:", str(e))
        raise
