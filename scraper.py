import requests
import json
import os
import time
import math
import urllib.parse

BASE_URL = "https://prod-api.trackprep.in/practice"
DATA_DIR = "data"
SLEEP_TIME = 1  # seconds between requests
RETRY_SLEEP = 60  # seconds to wait on rate limit

def make_request(url):
    while True:
        try:
            response = requests.get(url)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.HTTPError as e:
            if response.status_code == 429:
                print(f"Rate limited. Waiting {RETRY_SLEEP} seconds...")
                time.sleep(RETRY_SLEEP)
            else:
                raise e
        except Exception as e:
            print(f"Error fetching {url}: {e}")
            raise e

def ensure_dir(path):
    os.makedirs(path, exist_ok=True)

def save_questions(subject, chapter, topic, questions):
    subject_dir = os.path.join(DATA_DIR, subject.lower())
    ensure_dir(subject_dir)
    chapter_dir = os.path.join(subject_dir, chapter.lower().replace(' ', '_'))
    ensure_dir(chapter_dir)
    file_path = os.path.join(chapter_dir, f"{topic.lower().replace(' ', '_')}.json")
    with open(file_path, 'w', encoding='utf-8') as f:
        json.dump({"questions": questions}, f, indent=4)
    print(f"Saved {len(questions)} questions for {subject}/{chapter}/{topic}")

def fetch_filters():
    url = f"{BASE_URL}/filters"
    time.sleep(SLEEP_TIME)
    return make_request(url)

def fetch_chapters(subject):
    url = f"{BASE_URL}/chapters/{subject.lower()}"
    time.sleep(SLEEP_TIME)
    return make_request(url)

def fetch_topics(subject, chapter):
    encoded_chapter = urllib.parse.quote(chapter.lower())
    url = f"{BASE_URL}/topics/{subject.lower()}/{encoded_chapter}"
    time.sleep(SLEEP_TIME)
    return make_request(url)

def fetch_questions_page(subject, chapter, topic, page=1, limit=20):
    encoded_chapter = urllib.parse.quote_plus(chapter)
    encoded_topic = urllib.parse.quote_plus(topic)
    url = f"{BASE_URL}/questions?subject={subject}&chapter={encoded_chapter}&topic={encoded_topic}&page={page}&limit={limit}&sortBy=latest"
    time.sleep(SLEEP_TIME)
    data = make_request(url)
    return data.get('questions', []), data.get('total', 0)  # Assuming the response has 'questions' and maybe 'total'

def fetch_all_questions(subject, chapter, topic, qcount):
    all_questions = []
    limit = 20
    pages = math.ceil(qcount / limit) if qcount else 1
    for page in range(1, pages + 1):
        questions, total = fetch_questions_page(subject, chapter, topic, page, limit)
        all_questions.extend(questions)
        if total and len(all_questions) >= total:
            break
    return all_questions

def main():
    ensure_dir(DATA_DIR)
    
    filters = fetch_filters()
    subjects = filters.get('subjects', [])
    
    for subject in subjects:
        chapters = fetch_chapters(subject)
        for chap in chapters:
            chapter_name = chap['name']
            topics = fetch_topics(subject, chapter_name)
            for top in topics:
                topic_name = top['name']
                qcount = top['qcount']
                questions = fetch_all_questions(subject, chapter_name, topic_name, qcount)
                save_questions(subject, chapter_name, topic_name, questions)

if __name__ == "__main__":
    main()
