import os
import csv
from copy import deepcopy
from os.path import join, exists
import openai
import chromadb
from chromadb.utils.embedding_functions import OpenAIEmbeddingFunction
from datetime import datetime

# Configuration
ENDPOINT = "http://127.0.0.1:1234/v1/"
API_KEY = "none_needed"
MODELS = ['gemma-3-1b-it-qat', 'qwen3-0.6b', 'deepseek-r1-distill-qwen-1.5b']
DATASET_PATH = join('datasets', 'call_transcripts_scam_determinations.csv')
TEST_DIALOGS = join('datasets', 'agent_conversation_test.csv')
PERSIST_PATH = join('.', 'chroma_db')
COLLECTION_NAME = 'com643_collection'
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 200

# Initialize OpenAI client
openai.api_key = API_KEY
openai.base_url = ENDPOINT

# Initialize ChromaDB client and embeddings
client = chromadb.PersistentClient(path=PERSIST_PATH)
em_func = OpenAIEmbeddingFunction(
    api_key=API_KEY,
    model_name='text-embedding-mxbai-embed-large-v1',
    api_base=ENDPOINT
)

collection = client.get_or_create_collection(name=COLLECTION_NAME, embedding_function=em_func)

# Utility: simple recursive splitter
def split_text(text, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP):
    chunks = []
    start = 0
    length = len(text)
    while start < length:
        end = min(start + chunk_size, length)
        chunks.append(text[start:end])
        start += chunk_size - overlap
    return chunks

# Index documents if not already done
if not exists(PERSIST_PATH) or not collection.count():
    with open(DATASET_PATH, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f, fieldnames=[
            'CONVERSATION_ID', 'CONVERSATION_STEP', 'TEXT',
            'CONTEXT', 'LABEL', 'FEATURES', 'ANNOTATIONS'
        ])
        next(reader)
        ids, metadatas, embeddings_list = [], [], []
        for row in reader:
            text = row['TEXT']
            for chunk in split_text(text):
                uid = f"{row['CONVERSATION_ID']}_{row['CONVERSATION_STEP']}"
                if (uid in ids):
                    continue

                ids.append(uid)
                metadatas.append({
                    'conversation_id': row['CONVERSATION_ID'],
                    'context': row["CONTEXT"],
                    'label': row['LABEL']
                })
                embeddings_list.append(chunk)
        
        collection.add(
            documents=embeddings_list,
            ids=ids,
            metadatas=metadatas
        )

# Prompts
BINARY_PROMPT = (
    "Please analyze the call content and detect whether it is a fraud call." 
    "Please carefully analyze the suspicious features in the conversation. " 
    "If present, assess the MATCH, CLASS and REASON to determine if the call is a fraud or a normal call."
    "If it is a fraud call, please only return \"FRAUD\". " 
    "If it is a normal call, please only return \"SAFE\". " 
    "Do not return anything else. ")
UNCERTAIN_PROMPT = (
    "Please analyze the call content and detect whether it is a fraud call. "
    "Please carefully analyze the suspicious features in the conversation. "
    "If present, assess the MATCH, CLASS and REASON to determine if the call is a fraud or a normal call."
    "If it is a fraud call, please only return \"FRAUD\". "
    "If it is a normal call, please only return \"SAFE\". "
    "If there is insufficient information (e.g., it is not yet obvious that the fraud is present), please return \"UNCERTAIN\". "
    "Do not return anything else. ")

# Classification helper
def chat_completion(system_prompt: str, user_prompt: str, model: str) -> str | None:
    response = openai.chat.completions.create(
        model=model,
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': user_prompt}
        ],
        temperature=0
    )

    return None if response.choices is None else response.choices[0].message.content.strip().upper()

# Real-time classification
def classify_realtime(conversation: str, prompt_type: str, use_rag: bool, model: str) -> tuple[str, float]:
    time_before_decision = datetime.now()

    ongoing = ''
    last_answer = 'SAFE' if prompt_type == 'binary' else 'UNCERTAIN'
    lines = conversation.replace('Callee: ', '\nCallee: ').replace('Caller: ', '\nCaller: ').splitlines()[1:]

    for chunk in lines:
        ongoing += chunk + '\n'
        if use_rag:
            # embed query and retrieve
            result = collection.query(
                query_texts=[chunk],
                n_results=1
            )
            match = result['documents'][0]
            metadata = result['metadatas'][0][0]
            ongoing += (f"\nMATCH: \"{match}\", "
            f"\nCLASS: \"{metadata['label']}\", "
            f"\nREASON: \"{metadata['context']}\"")

        if prompt_type == 'binary':
            system_prompt = BINARY_PROMPT
        else:
            system_prompt = UNCERTAIN_PROMPT

        
        answer = chat_completion(system_prompt, ongoing, model)
        last_answer = answer

        if answer == 'FRAUD':
            break

    return last_answer, (datetime.now() - time_before_decision).total_seconds()

# Run analysis for each model
def run_analysis_for_model(model_name):
    print(f"Running analysis for {model_name}")
    # Load test dialogs
    with open(TEST_DIALOGS, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f, fieldnames=["dialog", "personality", "type", "scam?"])
        next(reader)
        calls = list(reader)

    for count, call in enumerate(calls, start=1):
        dialog = call['dialog']
        call['id'] = count
        call['rt'], call['rt_duration_s'] = classify_realtime(dialog, 'binary', False, model_name)
        call['unc'], call['unc_duration_s'] = classify_realtime(dialog, 'uncertain', False, model_name)
        call['rag_rt'], call['rag_rt_duration_s'] = classify_realtime(dialog, 'binary', True, model_name)
        call['rag_unc'], call['rag_unc_duration_s'] = classify_realtime(dialog, 'uncertain', True, model_name)

        label = "SAFE" if call['scam?'] == '0' else "FRAUD"
        print(f"Call #{count}, which is {label}, has been classed as: rt={call['rt']}, unc={call['unc']}, rag_rt={call['rag_rt']}, rag_unc={call['rag_unc']}")
        
    # Write results
    out = f"results_{model_name}.csv"
    with open(out, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ["dialog", "personality", "type", "scam?", "id", "rt", "rt_duration_s", "unc", "unc_duration_s", "rag_rt", "rag_rt_duration_s", "rag_unc", "rag_unc_duration_s"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(calls)
    print(f"Results saved to {out}")

for model in MODELS:
    run_analysis_for_model(model)