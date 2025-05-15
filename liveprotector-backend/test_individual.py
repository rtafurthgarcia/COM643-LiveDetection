import os
import csv
from copy import deepcopy
from os.path import join, exists
import openai
import chromadb
from chromadb.utils.embedding_functions import OpenAIEmbeddingFunction

# Configuration
ENDPOINT = "http://127.0.0.1:1234/v1"
API_KEY = "none_needed"
MODELS = ['gemma-3-1b-it-qat', 'qwen3-1.7b', 'deepseek-r1-distill-qwen-1.5b']
DATASET_PATH = join('datasets', 'call_transcripts_scam_determinations.csv')
TEST_DIALOGS = join('datasets', 'agent_conversation_test.csv')
PERSIST_PATH = join('.', 'chroma_db')
COLLECTION_NAME = 'com643_collection'
CHUNK_SIZE = 1000
CHUNK_OVERLAP = 200

# Initialize OpenAI client
openai.api_key = API_KEY
openai.api_base = ENDPOINT

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
                metadatas.append({'conversation_id': row['CONVERSATION_ID']})
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
    "If it is a fraud call, please only return \"FRAUD\". " 
    "If it is a normal call, please only return \"SAFE\". " 
    "Do not return anything else: {ongoing_conversation}")
UNCERTAIN_PROMPT = (
    "Please analyze the call content and detect whether it is a fraud call. "
    "Please carefully analyze the suspicious features in the conversation. "
    "If it is a fraud call, please only return \"FRAUD\". "
    "If it is a normal call, please only return \"SAFE\". "
    "If there is insufficient information (e.g., it is not yet obvious that the fraud is present), please return \"UNCERTAIN\". "
    "Do not return anything else: {ongoing_conversation}"
    "Here is the context: {context}")

# Classification helper
def chat_completion(system_prompt: str, user_prompt: str, model: str):
    response = openai.chat.completions.create(
        model=model,
        messages=[
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': user_prompt}
        ],
        temperature=0
    )
    return response.choices[0].message.content.strip().upper()

# Real-time classification
def classify_realtime(conversation: str, prompt_type: str, use_rag: bool, model: str):
    ongoing = ''
    last_answer = 'SAFE'
    lines = conversation.replace('Callee: ', '\nCallee: ').replace('Caller: ', '\nCaller: ').splitlines()[1:]

    for chunk in lines:
        ongoing += chunk + '\n'
        context = ''
        if use_rag:
            # embed query and retrieve
            result = collection.query(
                query_texts=[chunk],
                n_results=3
            )
            context = '\n'.join(result['documents'][0])

        if prompt_type == 'binary':
            user_prompt = BINARY_PROMPT + ongoing
        else:
            user_prompt = UNCERTAIN_PROMPT.format(context=context) + ongoing

        answer = chat_completion('', user_prompt, model)
        if answer == 'FRAUD':
            return 'FRAUD'
        last_answer = answer

    return last_answer

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
        call['rt'] = classify_realtime(dialog, 'binary', False, model_name)
        call['unc'] = classify_realtime(dialog, 'uncertain', False, model_name)
        call['rag_rt'] = classify_realtime(dialog, 'binary', True, model_name)
        call['rag_unc'] = classify_realtime(dialog, 'uncertain', True, model_name)
        print(f"Call #{count}: rt={call['rt']}, unc={call['unc']}, rag_rt={call['rag_rt']}, rag_unc={call['rag_unc']}")

    # Write results
    out = f"results_{model_name}.csv"
    with open(out, 'w', newline='', encoding='utf-8') as csvfile:
        fieldnames = ["dialog", "personality", "type", "scam?", "id", "rt", "unc", "rag_rt", "rag_unc"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(calls)
    print(f"Results saved to {out}")

for model in MODELS:
    run_analysis_for_model(model)